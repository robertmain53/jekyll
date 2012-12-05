module Jekyll

  class Site
    attr_accessor :config, :layouts, :posts, :pages, :static_files, :photos,
                  :categories, :exclude, :source, :dest, :lsi, :pygments,
                  :permalink_style, :tags, :time, :future, :safe, :plugins, :limit_posts, :collated

    attr_accessor :converters, :generators

    # Initialize the site
    #   +config+ is a Hash containing site configurations details
    #
    # Returns <Site>
    def initialize(config)
      self.config          = config.clone

      self.safe            = config['safe']
      self.source          = File.expand_path(config['source'])
      self.dest            = File.expand_path(config['destination'])
      self.plugins         = File.expand_path(config['plugins'])
      self.lsi             = config['lsi']
      self.pygments        = config['pygments']
      self.permalink_style = config['permalink'].to_sym
      self.exclude         = config['exclude'] || []
      self.future          = config['future']
      self.limit_posts     = config['limit_posts'] || nil

      self.reset
      self.setup
    end

    def reset
      self.time            = if self.config['time']
                               Time.parse(self.config['time'].to_s)
                             else
                               Time.now
                             end
      self.layouts         = {}
      self.posts           = []
      self.pages           = []
      self.photos          = []
      self.static_files    = []
      self.categories      = Hash.new { |hash, key| hash[key] = [] }
      self.tags            = Hash.new { |hash, key| hash[key] = [] }
      self.collated        = {}
      raise ArgumentError, "Limit posts must be nil or >= 1" if !self.limit_posts.nil? && self.limit_posts < 1
    end

    def setup
      require 'classifier' if self.lsi
    
      # If safe mode is off, load in any ruby files under the plugins
      # directory.
      unless self.safe
        Dir[File.join(self.plugins, "**/*.rb")].each do |f|
          require f
        end
      end

      self.converters = Jekyll::Converter.subclasses.select do |c|
        !self.safe || c.safe
      end.map do |c|
        c.new(self.config)
      end

      self.generators = Jekyll::Generator.subclasses.select do |c|
        !self.safe || c.safe
      end.map do |c|
        c.new(self.config)
      end
    end

    # Do the actual work of processing the site and generating the
    # real deal.  5 phases; reset, read, generate, render, write.  This allows
    # rendering to have full site payload available.
    #
    # Returns nothing
    def process
      self.reset
      self.read
      self.generate
      self.render
      self.cleanup
      self.write
      self.write_archives
    end

    def read
      self.read_layouts # existing implementation did this at top level only so preserved that
      self.read_directories
    end

    # Read all the files in <source>/<dir>/_layouts and create a new Layout
    # object with each one.
    #
    # Returns nothing
    def read_layouts(dir = '')
      base = File.join(self.source, dir, "_layouts")
      return unless File.exists?(base)
      entries = []
      Dir.chdir(base) { entries = filter_entries(Dir['*.*']) }

      entries.each do |f|
        name = f.split(".")[0..-2].join(".")
        self.layouts[name] = Layout.new(self, base, f)
      end
    end

    # Read all the files in <source>/<dir>/_posts and create a new Post
    # object with each one.
    #
    # Returns nothing
    def read_posts(dir)
      base = File.join(self.source, dir, '_posts')
      return unless File.exists?(base)
      entries = Dir.chdir(base) { filter_entries(Dir['**/*']) }

      # first pass processes, but does not yet render post content
      entries.each do |f|
        if Post.valid?(f)
          post = Post.new(self, self.source, dir, f)

          if post.published && (self.future || post.date <= self.time)
            self.posts << post
            post.categories.each { |c| self.categories[c] << post }
            post.tags.each { |c| self.tags[c] << post }
          end
        end
      end

      self.posts.sort!

      # limit the posts if :limit_posts option is set
      self.posts = self.posts[-limit_posts, limit_posts] if limit_posts
    end
    
    # Read all the files in <source>/<dir>/_photos and create a new photo
    # object with each one.
    #
    # Returns nothing
    def read_photos(dir)
      base = File.join(self.source, dir, '_photos')
      return unless File.exists?(base)
      entries = Dir.chdir(base) { filter_entries(Dir['**/*']) }

      # first pass processes, but does not yet render post content
      entries.each do |f|
        if Photo.valid?(f)
          photo = Photo.new(self, self.source, dir, f)

          if photo.published && (self.future || photo.date <= self.time)
            self.photos << photo
            photo.categories.each { |c| self.categories[c] << photo }
            photo.tags.each { |c| self.tags[c] << photo }
          end
        end
      end

      self.photos.sort!

      # limit the posts if :limit_photos option is set
      #self.photos = self.photos[-limit_photos, limit_photos] if limit_photos
    end

    def generate
      self.generators.each do |generator|
        generator.generate(self)
      end
    end

    def render
      self.posts.reverse.each do |post|
        y, m, d = post.date.year, post.date.month, post.date.day
        unless self.collated.key? y
          self.collated[ y ] = {}
        end
        unless self.collated[y].key? m
          self.collated[ y ][ m ] = {}
        end
        unless self.collated[ y ][ m ].key? d
          self.collated[ y ][ m ][ d ] = []
        end
        self.collated[ y ][ m ][ d ] += [ post ]
      end
      
      self.posts.each do |post|
        post.render(self.layouts, site_payload)
      end
      
      self.photos.each do |photo|
        photo.render(self.layouts, site_payload)
      end

      self.pages.each do |page|
        page.render(self.layouts, site_payload)
      end

      self.categories.values.map { |ps| ps.sort! { |a, b| b <=> a} }
      self.tags.values.map { |ps| ps.sort! { |a, b| b <=> a} }
    rescue Errno::ENOENT => e
      # ignore missing layout dir
    end
    
    # Remove orphaned files and empty directories in destination
    #
    # Returns nothing
    def cleanup
      # all files and directories in destination, including hidden ones
      dest_files = []
      Dir.glob(File.join(self.dest, "**", "*"), File::FNM_DOTMATCH) do |file|
        dest_files << file unless file =~ /\/\.{1,2}$/
      end

      # files to be written
      files = []
      self.posts.each do |post|
        files << post.destination(self.dest)
      end
      self.photos.each do |photo|
        files << photo.destination(self.dest)
      end
      self.pages.each do |page|
        files << page.destination(self.dest)
      end
      self.static_files.each do |sf|
        files << sf.destination(self.dest)
      end
      
      # adding files' parent directories
      files.each { |file| files << File.dirname(file) unless files.include? File.dirname(file) }
      
      obsolete_files = dest_files - files
      
      FileUtils.rm_rf(obsolete_files)
    end

    # Write static files, pages, posts and photos
    #
    # Returns nothing
    def write
      self.posts.each do |post|
        post.write(self.dest)
      end
      self.photos.each do |photo|
        photo.write(self.dest)
      end
      self.pages.each do |page|
        page.write(self.dest)
      end
      self.static_files.each do |sf|
        sf.write(self.dest)
      end
    end
    
    #   Write post archives to <dest>/<year>/, <dest>/<year>/<month>/
    #   Use layouts called archive_yearly and archive_monthly if avail
    #
    #   Returns nothing
    def write_archive( dir, type )
        archive = Archive.new( self, self.source, dir, type )
        archive.render( self.layouts, site_payload )
        archive.write( self.dest )
    end
    
    def write_archives
      self.collated.keys.each do |y|
          if self.layouts.key? 'archive_yearly'
              self.write_archive( y.to_s, 'archive_yearly' )
          end

          self.collated[ y ].keys.each do |m|
              if self.layouts.key? 'archive_monthly'
                  self.write_archive( "%04d/%02d" % [ y.to_s, m.to_s ], 'archive_monthly' )
              end

              self.collated[ y ][ m ].keys.each do |d|
                  if self.layouts.key? 'archive_daily'
                      self.write_archive( "%04d/%02d/%02d" % [ y.to_s, m.to_s, d.to_s ], 'archive_daily' )
                  end
              end
          end
      end
    end
    
    # Reads the directories and finds posts, pages and static files that will
    # become part of the valid site according to the rules in +filter_entries+.
    #   The +dir+ String is a relative path used to call this method
    #            recursively as it descends through directories
    #
    # Returns nothing
    def read_directories(dir = '')
      base = File.join(self.source, dir)
      entries = filter_entries(Dir.entries(base))

      self.read_posts(dir)
      self.read_photos(dir)

      entries.each do |f|
        f_abs = File.join(base, f)
        f_rel = File.join(dir, f)
        if File.directory?(f_abs)
          next if self.dest.sub(/\/$/, '') == f_abs
          read_directories(f_rel)
        elsif !File.symlink?(f_abs)
          first3 = File.open(f_abs) { |fd| fd.read(3) }
          if first3 == "---"
            # file appears to have a YAML header so process it as a page
            pages << Page.new(self, self.source, dir, f)
          else
            # otherwise treat it as a static file
            static_files << StaticFile.new(self, self.source, dir, f)
          end
        end
      end
    end
    

    # Constructs a hash map of Posts indexed by the specified Post attribute
    #
    # Returns {post_attr => [<Post>]}
    def post_attr_hash(post_attr)
      # Build a hash map based on the specified post attribute ( post attr => array of posts )
      # then sort each array in reverse order
      hash = Hash.new { |hash, key| hash[key] = Array.new }
      self.posts.each { |p| p.send(post_attr.to_sym).each { |t| hash[t] << p } }
      hash.values.map { |sortme| sortme.sort! { |a, b| b <=> a} }
      return hash
    end
    
    # The Hash payload containing site-wide data
    #
    # Returns {"site" => {"time" => <Time>,
    #                     "posts" => [<Post>],
    #                     "collated_posts" => [<Post>],
    #                     "pages" => [<Page>],
    #                     "categories" => [<Post>]}
    def site_payload
      {"site" => self.config.merge({
          "time"            => self.time,
          "posts"           => self.posts.sort { |a,b| b <=> a },
          "photos"          => self.photos.sort { |a,b| b <=> a },
          "collated_posts"  => self.collated,
          "pages"           => self.pages,
          "html_pages"      => self.pages.reject { |page| !page.html? },
          "categories"      => post_attr_hash('categories'),
          "tags"            => post_attr_hash('tags')})}
    end

    # Filter out any files/directories that are hidden or backup files (start
    # with "." or "#" or end with "~"), or contain site content (start with "_"),
    # or are excluded in the site configuration, unless they are web server
    # files such as '.htaccess'
    def filter_entries(entries)
      entries = entries.reject do |e|
        unless ['.htaccess'].include?(e)
          ['.', '_', '#'].include?(e[0..0]) || e[-1..-1] == '~' || self.exclude.include?(e)
        end
      end
    end

  end
end

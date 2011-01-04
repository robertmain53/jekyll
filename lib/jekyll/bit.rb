module Jekyll

  class Bit
    include Comparable
    include Convertible

    class << self
      attr_accessor :lsi
    end

    MATCHER = /^(.+\/)*(\d+-\d+-\d+)-(.*)(\.[^.]+)$/

    # Bit name validator. Bit filenames must be like:
    #   2008-11-05-my-awesome-bit.textile
    #
    # Returns <Bool>
    def self.valid?(name)
      name =~ MATCHER
    end

    attr_accessor :site
    attr_accessor :data, :content, :output, :ext
    attr_accessor :date, :slug, :published, :tags, :categories

    # Initialize this Bit instance.
    #   +site+ is the Site
    #   +base+ is the String path to the dir containing the bit file
    #   +name+ is the String filename of the bit file
    #   +categories+ is an Array of Strings for the categories for this bit
    #
    # Returns <Bit>
    def initialize(site, source, dir, name)
      @site = site
      @base = File.join(source, dir, '_bits')
      @name = name

      self.categories = dir.split('/').reject { |x| x.empty? }
      self.process(name)
      self.read_yaml(@base, name)

      #If we've added a date and time to the yaml, use that instead of the filename date
      #Means we'll sort correctly.
      if self.data.has_key?('date')
        # ensure Time via to_s and reparse
        self.date = Time.parse(self.data["date"].to_s)
      end

      if self.data.has_key?('published') && self.data['published'] == false
        self.published = false
      else
        self.published = true
      end

      self.tags = self.data.pluralized_array("tag", "tags")

      if self.categories.empty?
        self.categories = self.data.pluralized_array('category', 'categories')
      end
    end

    # Spaceship is based on Bit#date, slug
    #
    # Returns -1, 0, 1
    def <=>(other)
      cmp = self.date <=> other.date
      if 0 == cmp
       cmp = self.slug <=> other.slug
      end
      return cmp
    end

    # Extract information from the bit filename
    #   +name+ is the String filename of the bit file
    #
    # Returns nothing
    def process(name)
      m, cats, date, slug, ext = *name.match(MATCHER)
      self.date = Time.parse(date)
      self.slug = slug
      self.ext = ext
    end

    # The generated directory into which the bit will be placed
    # upon generation. This is derived from the permalink or, if
    # permalink is absent, set to the default date
    # e.g. "/2008/11/05/" if the permalink style is :date, otherwise nothing
    #
    # Returns <String>
    def dir
      File.dirname(generated_path)
    end

    # The full path and filename of the bit.
    # Defined in the YAML of the bit body
    # (Optional)
    #
    # Returns <String>
    def permalink
      self.data && self.data['permalink']
    end

    def template
      case self.site.permalink_style
      when :pretty
        "/:categories/:year/:month/:day/:title/"
      when :none
        "/:categories/:title.html"
      when :date
        "/:categories/:year/:month/:day/:title.html"
      else
        self.site.permalink_style.to_s
      end
    end

    # The generated relative url of this bit
    # e.g. /2008/11/05/my-awesome-bit.html
    #
    # Returns <String>
    def generated_path
      return permalink if permalink

      @generated_path ||= {
        "year"       => date.strftime("%Y"),
        "month"      => date.strftime("%m"),
        "day"        => date.strftime("%d"),
        "title"      => CGI.escape(slug),
        "i_day"      => date.strftime("%d").to_i.to_s,
        "i_month"    => date.strftime("%m").to_i.to_s,
        "categories" => categories.join('/'),
        "output_ext" => self.output_ext
      }.inject(template) { |result, token|
        result.gsub(/:#{Regexp.escape token.first}/, token.last)
      }.gsub(/\/\//, "/")
    end
    
    # The generated relative url of this bit
    # e.g. /2008/11/05/my-awesome-bit
    #
    # Returns <String>
    def url
      site.config['multiviews'] ? generated_path.sub(/\.html$/, '') : generated_path
    end

    # The UID for this bit (useful in feeds)
    # e.g. /2008/11/05/my-awesome-bit
    #
    # Returns <String>
    def id
      File.join(self.dir, self.slug)
    end

    # Calculate related bits.
    #
    # Returns [<Bit>]
    def related_bits(bits)
      return [] unless bits.size > 1

      if self.site.lsi
        self.class.lsi ||= begin
          puts "Running the classifier... this could take a while."
          lsi = Classifier::LSI.new
          bits.each { |x| $stdout.print(".");$stdout.flush;lsi.add_item(x) }
          puts ""
          lsi
        end

        related = self.class.lsi.find_related(self.content, 11)
        related - [self]
      else
        (bits - [self])[0..9]
      end
    end

    # Add any necessary layouts to this bit
    #   +layouts+ is a Hash of {"name" => "layout"}
    #   +site_payload+ is the site payload hash
    #
    # Returns nothing
    def render(layouts, site_payload)
      # construct payload
      payload = {
        "site" => { "related_bits" => related_bits(site_payload["site"]["bits"]) },
        "page" => self.to_liquid
      }.deep_merge(site_payload)

      do_layout(payload, layouts)
    end
    
    # Obtain destination path.
    #   +dest+ is the String path to the destination dir
    #
    # Returns destination file path.
    def destination(dest)
      # The url needs to be unescaped in order to preserve the correct filename
      path = File.join(dest, CGI.unescape(self.generated_path))
      path = File.join(path, "index.html") if template[/\.html$/].nil?
      path
    end

    # Write the generated bit file to the destination directory.
    #   +dest+ is the String path to the destination dir
    #
    # Returns nothing
    def write(dest)
      path = destination(dest)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, 'w') do |f|
        f.write(self.output)
      end
    end

    # Convert this bit into a Hash for use in Liquid templates.
    #
    # Returns <Hash>
    def to_liquid
      self.data.deep_merge({
        "title"      => self.data["title"] || self.slug.split('-').select {|w| w.capitalize! || w }.join(' '),
        "url"        => self.url,
        "date"       => self.date,
        "id"         => self.id,
        "categories" => self.categories,
        "folded" => (self.content.match("<!--more-->") ? true : false),
        "next"       => self.next,
        "previous"   => self.previous,
        "tags"       => self.tags,
        "content"    => self.content })
    end

    def inspect
      "<Bit: #{self.id}>"
    end

    def next
      pos = self.site.bits.index(self)

      if pos && pos < self.site.bits.length-1
        self.site.bits[pos+1]
      else
        nil
      end
    end

    def previous
      pos = self.site.bits.index(self)
      if pos && pos > 0
        self.site.bits[pos-1]
      else
        nil
      end
    end
  end

end

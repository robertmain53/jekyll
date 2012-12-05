require 'uri'
require 'fastimage'

module Jekyll

  module Filters
    def textilize(input)
      #RedCloth.new(input).to_html
      TextileConverter.new.convert(input)
    end

    def markdownize(input)
      if input
        if defined? RDiscount
          RDiscount.new(input, :smart).to_html 
        elsif defined? Maruku
          Maruku.new(input, :smart).to_html
        else
          input
        end
      else
        ''
      end
    end

    def date_to_string_formatted(date)
      date.strftime("<span class='day'>%d</span><span class='month'>%b</span><span class='year'>%Y</span>")
    end

    def date_to_string(date)
      date.strftime("%d %b %Y")
    end

    def date_to_long_string(date)
      date.strftime("%d %B %Y")
    end
    
    def date_to_long_day(date)
      day = date.strftime("%d").to_i
      if (day == 1 || day == 21 || day == 31)
        long_day = 'st'
      elsif (day == 2 || day == 22)
        long_day = 'nd'
      elsif (day == 3 || day == 23)
        long_day = 'rd'
      else
        long_day = 'th'
      end
      return day.to_s + long_day
    end

    def date_to_xmlschema(date)
      date.xmlschema
    end

    def xml_escape(input)
      CGI.escapeHTML(input)
    end

    def cgi_escape(input)
      CGI::escape(input)
    end

    def uri_escape(input)
      URI.escape(input)
    end

    def number_of_words(input)
      input.split.length
    end
    
    # Returns all content before the first-encountered WP-style MORE tag.
    # Allows authors to mark the fold with an <!--more--> in their drafts.
    # e.g. {{ content | before_fold }}
    def before_fold(input, url, title)
      if input.include? "<!--more-->"
        input.split("<!--more-->").first + " <a class='read_more' title='#{title}' href='#{url}'>Continue Reading &rarr;</a>"
      else
        input
      end
    end

    def image_width(url)
      url = "http://stammy.imgix.net/" + url
      FastImage.size(url).first
    end

    def image_height(url)
      url = "http://stammy.imgix.net/" + url
      FastImage.size(url).last
    end
    
    def to_month(input)
      return Date::MONTHNAMES[input.to_i]
    end

    def to_month_abbr(input)
      return Date::ABBR_MONTHNAMES[input.to_i]
    end

    def array_to_sentence_string(array)
      connector = "and"
      case array.length
      when 0
        ""
      when 1
        array[0].to_s
      when 2
        "#{array[0]} #{connector} #{array[1]}"
      else
        "#{array[0...-1].join(', ')}, #{connector} #{array[-1]}"
      end
    end

  end
end

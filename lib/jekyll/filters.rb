require 'uri'

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

    def date_to_string(date)
      date.strftime("%d %b %Y")
    end

    def date_to_long_string(date)
      date.strftime("%d %B %Y")
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
    def before_fold(input)
      input.split("<!--more-->").first
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

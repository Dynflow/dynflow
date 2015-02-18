module Jekyll
  module FancyToCFilter
    def fancytoc(input)

      converter  = @context.registers[:site].converters.find { |c| c.is_a? Jekyll::Converters::Markdown }
      extensions = converter.instance_variable_get(:@parser).instance_variable_get(:@redcarpet_extensions)
      converter  = Redcarpet::Markdown.new(Redcarpet::Render::HTML_TOC, extensions)
      toc        = converter.render(input)

      '<div class="toc well">' + toc + '</div>' unless toc.empty?
    end
  end
end

Liquid::Template.register_filter(Jekyll::FancyToCFilter)

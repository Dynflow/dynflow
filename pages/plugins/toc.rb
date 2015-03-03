module Jekyll
  module FancyToCFilter
    def fancytoc(input)

      converter     = @context.registers[:site].converters.find { |c| c.is_a? Jekyll::Converters::Markdown }
      extensions    = converter.instance_variable_get(:@parser).instance_variable_get(:@redcarpet_extensions)
      toc_generator = Redcarpet::Markdown.new(Redcarpet::Render::HTML_TOC, extensions)
      toc           = toc_generator.render(input)

      <<-HTML unless toc.empty?
        <div class="toc well" data-spy="affix" data-offset-top="0" data-offset-bottom="0">
          <h4>Table of content</h4>
          #{toc}
        </div>
      HTML
    end
  end
end

Liquid::Template.register_filter(Jekyll::FancyToCFilter)

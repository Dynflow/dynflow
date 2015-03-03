module Jekyll
  class DivTag < Liquid::Block
    def render(context)
      content            = super

      <<-HTML.gsub(/^ +\|/, '')
        |<#{tag} class="#{@markup}">
        |  #{render_content context, content}
        |</#{tag}>
      HTML
    end

    def tag
      @tag_name.split('_').first
    end

    def render_content(context, content)
      converter          = context.registers[:site].converters.find { |c| c.is_a? Jekyll::Converters::Markdown }
      extensions         = converter.instance_variable_get(:@parser).instance_variable_get(:@redcarpet_extensions)
      markdown_generator = Redcarpet::Markdown.new(Redcarpet::Render::HTML, extensions)
      markdown_generator.render(content)
    end
  end
end

Liquid::Template.register_tag('div_tag', Jekyll::DivTag)
Liquid::Template.register_tag('span_tag', Jekyll::DivTag)

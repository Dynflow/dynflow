module Jekyll
  class DivTag < Liquid::Block
    def render(context)
      content = super

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
      context.registers[:site].converters.find { |c| c.is_a? Jekyll::Converters::Markdown }.convert(content)
    end
  end
end

Liquid::Template.register_tag('div_tag', Jekyll::DivTag)
Liquid::Template.register_tag('span_tag', Jekyll::DivTag)

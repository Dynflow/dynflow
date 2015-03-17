# taken from https://raw.githubusercontent.com/kui/octopress-graphviz/master/graphviz_block.rb

require 'open3'

module Jekyll
  class GraphvizBlock < Liquid::Block

    DIV_CLASS_ATTR     = 'graphviz-wrapper'
    DEFAULT_GRAPH_NAME = 'Graphviz'
    DOT_OPTS           = '-Tsvg'
    DOT_EXEC           = 'dot'
    DOT_EXTS           = (ENV['PATHEXT'] || '.exe;.bat;.com').split(";")
    DOT_EXTS.unshift ''
    DOT_PATH = ENV['PATH'].split(File::PATH_SEPARATOR)
                   .map { |a| File.join a, DOT_EXEC }
                   .map { |a| DOT_EXTS.map { |ex| a+ex } }.flatten
                   .find { |c| File.executable_real? c }
    raise "not found a executable file: #{DOT_EXEC}" if DOT_PATH.nil?
    DOT_CMD = "#{DOT_PATH} #{DOT_OPTS}"

    def initialize(tag_name, markup, tokens)
      super
      @tag_name = tag_name

      @title = markup or ""
      @title.strip!

      @src = ""
    end

    def render(context)
      code  = super
      title = if @title.empty? then
                DEFAULT_GRAPH_NAME
              else
                @title
              end

      case @tag_name
      when 'graphviz' then
        render_graphviz code
      when 'graph' then
        render_graph 'graph', title, code
      when 'digraph' then
        render_graph 'digraph', title, code
      else
        raise "unknown liquid tag name: #{@tag_name}"
      end
    end

    def render_graphviz(code)
      @src = code
      svg  = generate_svg code
      filter_for_inline_svg svg
    end

    def filter_for_inline_svg(code)
      code = remove_declarations code
      code = remove_xmlns_attrs code
      code = add_desc_attrs code
      code = insert_desc_elements code
      code = wrap_with_div code
      code = code.gsub /<polygon fill="white" stroke="none"/, '<polygon fill="transparent" stroke="none"'
      code
    end

    def generate_svg code
      Open3.popen3(DOT_CMD) do |stdin, stdout, stderr|
        stdout.binmode
        stdin.print code
        stdin.close

        err = stderr.read
        if not (err.nil? || err.strip.empty?)
          raise "Error from #{DOT_CMD}:\n#{err}"
        end

        svg = stdout.read
        svg.force_encoding 'UTF-8'

        return svg
      end
    end

    def remove_declarations(svg)
      svg.sub(/<!DOCTYPE .+?>/im, '').sub(/<\?xml .+?\?>/im, '')
    end

    def remove_xmlns_attrs(svg)
      svg.sub(%[xmlns="http://www.w3.org/2000/svg"], '')
          .sub(%[xmlns:xlink="http://www.w3.org/1999/xlink"], '')
    end

    def add_desc_attrs(svg)
      svg.sub!("<svg", %[<svg aria-label="#{CGI::escapeHTML @title}"])
      svg.sub!("<svg", %[<svg role="img"])

      return svg
    end

    def insert_desc_elements(svg)
      inserted_elements = %[<title>#{CGI::escapeHTML @title}</title>\n]
      inserted_elements << %[<desc>#{CGI::escapeHTML @src}</desc>\n]
      svg.sub!(/(<svg [^>]*>)/, "\\1\n#{inserted_elements}")

      return svg
    end

    def wrap_with_div(svg)
      %[<div class="#{DIV_CLASS_ATTR}">#{svg}</div>]
    end

    def render_graph(type, title, code)
      render_graphviz %[#{type} "#{title}" { #{code} }]
    end
  end
end

Liquid::Template.register_tag('graphviz', Jekyll::GraphvizBlock)
Liquid::Template.register_tag('graph', Jekyll::GraphvizBlock)
Liquid::Template.register_tag('digraph', Jekyll::GraphvizBlock)

require 'zlib'
require 'archive/tar/minitar'

module Dynflow
  module Exporters
    class Tar < Abstract

      class << self

        def full_html_export(plans)
          html = Exporters::HTML.new(plans.first.world)
          tar = self.new(html, :with_assets => true,
                         :with_index  => true,
                         :filetype    => 'html')
          tar.add_many(plans)
            .add_file('worlds.html', html.export_worlds)
            .finalize.result
        end

        def full_json_export(plans)
          tar = self.new(Exporters::JSON.new(nil, :with_sub_plans => false),
                         :filetype => 'json')
          tar.add_many(plans).finalize.result
        end

      end

      def initialize(exporter, options = {})
        @exporter = exporter
        @buffer = options.fetch(:io, StringIO.new(""))
        @gzip = Zlib::GzipWriter.new(@buffer)
        @tar = Archive::Tar::Minitar::Output.new(@gzip)
        @options = options
      end

      def finalize
        @exporter.finalize

        add_assets if @options[:with_assets]
        add_file('index.' + @options[:filetype], @exporter.export_index) if @options[:with_index]

        @exporter.index.each do |key, value|
          add_file(key + '.' + @options[:filetype], value[:result])
        end

        @tar.close
        self
      end

      def result
        @buffer.string
      end

      def add_file(path, contents)
        @tar.tar.add_file_simple(path, :mode => 0664, :size => contents.size) do |stream|
          stream.write(contents)
        end
        self
      end

      def add(execution_plan)
        @exporter.add(execution_plan)
        self
      end

      def add_id(execution_plan_id)
        @exporter.add_id(execution_plan_id)
        self
      end

      def add_assets
        Dir.chdir(::Dynflow::Web.web_dir('/assets')) do
          Dir["**/*"].each do |asset|
            Archive::Tar::Minitar.pack_file(asset, @tar)
          end
        end
        self
      end
    end
  end
end

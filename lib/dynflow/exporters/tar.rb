require 'zlib'
require 'rubygems/package'

module Dynflow
  module Exporters
    class Tar < ExportManager

      FILE_MODE = 0644
      DIR_MODE  = 0775

      def self.prepare_html_export(io, plans, world)
        html = Exporters::HTML.new(world, :collect_index => true)
        tar = self.new(world, html, io,
                       :with_assets => true,
                       :with_index  => true)
        tar.add_file('worlds.html', html.export_worlds)
      end

      def initialize(world, exporter, io, options = {})
        super(world, exporter, io, options)
        @tar = Gem::Package::TarWriter.new(io)
      end

      def export_collection
        add_assets if @options[:with_assets]

        each do |uuid, content, _|
          add_file("#{uuid}.#{@exporter.filetype}", content)
          yield uuid if block_given?
        end
        add_file('index.' + @exporter.filetype, @exporter.export_index) if @options[:with_index]
        @tar.close
        self
      end

      def add_file(path, contents, size = contents.bytesize)
        @tar.add_file_simple(path, FILE_MODE, size) do |stream|
          stream.write(contents)
        end
        self
      end

      def add_assets
        Dir.chdir(::Dynflow::Web.web_dir('/assets')) do
          Dir["**/*"].each do |asset|
            if File.directory?(asset)
              @tar.mkdir(asset, DIR_MODE)
            else
              add_file_path(asset)
            end
          end
        end
        self
      end

      private

      def add_file_path(path)
        File.open(path) do |f|
          add_file(path, f.read, f.size)
        end
      end
    end
  end
end

module Dynflow
  module Exporters
    class Tar

      class << self

        def full_html_export(plans, console)
          exporter = Exporters::HTML.new(plans, :console => console)
          index = exporter.export_index

          arr = plans.map { |plan| plan.id + '.html' }
                   .zip(exporter.export_all_plans)

          self.new.add_assets.add(::Hash[arr].merge('index.html' => index)).finalize
        end

        def full_json_export(plans)
          all_plans = plans.reduce({}) do |acc, plan|
            exported = Exporters::Hash.export_execution_plan(plan, :with_full_sub_plans => false).to_json
            acc.merge("#{plan.id}.json" => exported)
          end
          new.add(all_plans).finalize
        end

      end

      def initialize
        @buffer = StringIO.new("")
        @gzip = Zlib::GzipWriter.new(@buffer)
        @tar = Archive::Tar::Minitar::Output.new(@gzip)
      end

      def finalize
        @tar.close
        @buffer.string
      end

      def add_file(path, contents)
        @tar.tar.add_file_simple(path, :mode => 0664, :size => contents.size) do |stream|
          stream.write(contents)
        end
        self
      end

      def add(files_hash)
        raise 'Must be a hash' unless files_hash.is_a? ::Hash
        files_hash.each do |path, contents|
          add_file(path, contents)
        end
        self
      end

      def add_assets
        Dir.chdir('web/assets') do
          Dir["**/*"].each do |asset|
            Archive::Tar::Minitar.pack_file(asset, @tar)
          end
        end
        self
      end
    end
  end
end

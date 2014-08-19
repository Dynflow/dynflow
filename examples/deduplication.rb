#!/usr/bin/env ruby

def example_description(id1, id2)

example_description = <<DESC
  Package Management Example
  ===================

  This example simulates a workflow of setting up a work environment, using
  more high-level steps in SetUpWorkplace, that expand to smaller steps
  of InstallPackage, GitClone, etc...

  It shows the possibility to detect duplicate actions and handle them adequately,
  not executing actions which were already done and were not marked to run always.

  One important thing. Deduplication handles ONLY run and finalize phases,
  it will NOT handle recursion.

  The SetUpWorkplace was planned twice, once with and once without deduplication
  enabled. Once the Sinatra web console starts you can navigate to
  http://localhost:4567/#{id1} (regular)
  http://localhost:4567/#{id2} (deduplicated)
  to see the difference deduplication makes.

DESC
end

require_relative 'example_helper'

module PackageManagement

  class Base < Dynflow::Action
    def sleep!
      sleep(rand(2))
    end
  end

  class SetUpWorkplace < Dynflow::Action

    def plan(deduplication_allowed = false)
      # allow the deduplication
      deduplicate! if deduplication_allowed
      sequence do
        # Refresh the repositories to get the latest packages
        index = plan_action(PackageManagement::RefreshRepositories)
        concurrence do
          # Install your editor, terminal multiplexer, whatever you might need
          plan_action(PackageManagement::InstallPackage, "vim.rpm")
          plan_action(PackageManagement::InstallPackage, "tmux.rpm")
          plan_action(PackageManagement::InstallPackage,
                      "something_from_external_repo.rpm",
                      "ftp.external.repo.io")
        end
      end
      # Clone your repository with configs
      plan_action(PackageManagement::GitClone,
                  :url => "https://github.com/someone/somerepo.git",
                  :path => "/home/userX")
      plan_self
    end

    def finalize
      output[:response] = "All is well"
    end

  end

  class RefreshRepositories < Base
    
    def plan
      # run_always! makes the action to be executed every time it is planned
      run_always!
      plan_self
    end

    def run
      sleep!
    end

  end

  class InstallPackage < Base
    # In sequence add external repository (if provided), install dependencies for package, download package and install it

    input_format do
      param :path
      param :name
    end

    def plan(package, repository = nil)
      sequence do
        plan_action(PackageManagement::AddRepository, repository) unless repository.nil?
        # ultimate_library... is needed by all packages except itself and has no dependencies
        plan_action(PackageManagement::InstallDependencies, package) unless package == "ultimate_lib_everything_needs.rpm"
        package_download = plan_action(PackageManagement::DownloadPackage, package, repository)
        plan_self(:name => package, :path => package_download.output[:path])
      end
    end

    def run
      sleep!
    end
    
    def finalize
      output[:response] = "Package #{input[:name]} was installed."
    end

  end

  class InstallDependencies < Base
    # Plan installation of needed packages, in here it's only ultimate_lib... for everything

    def plan(package)
      plan_action(PackageManagement::InstallPackage, "ultimate_lib_everything_needs.rpm")
    end

  end

  class DownloadPackage < Base
    # This action will be executed only once for one input

    input_format do
      param :url
    end

    output_format do
      param :path
    end

    def plan(package, mirror = nil)
      mirror ||= "ftp.mirror1.packages.org"
      plan_self(:url => "#{mirror}/#{package}")
    end

    def run
      sleep!
      output[:path] = "/var/cache/yum/#{File.basename(input[:url])}"
    end

  end

  class AddRepository < Base
    # Add the repository and refresh repositories to get info about what it provides

    input_format do
      param :url
    end

    def plan(url)
      sequence do
        plan_self(:url => url)
        plan_action(PackageManagement::RefreshRepositories)
      end
    end

    def run
      sleep!
    end

    def finalize
      output[:response] = "Repository #{input[:url]} was added."
    end

  end

  class GitClone < Base

    input_format do
      param :url
      param :path
    end

    def run
      sleep!
    end

  end

end

if $0 == __FILE__
  id1 = ExampleHelper.world.trigger(PackageManagement::SetUpWorkplace).execution_plan_id
  id2 = ExampleHelper.world.trigger(PackageManagement::SetUpWorkplace, true).execution_plan_id
  puts example_description(id1, id2)
  ExampleHelper.run_web_console
end

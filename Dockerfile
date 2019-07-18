FROM fedora:30
RUN dnf install -y curl git gcc gcc-c++ make openssl bzip2 findutils openssl-devel readline-devel \
                   zlib-devel sqlite-devel ruby ruby-devel rubygem-bundler redhat-rpm-config libpqxx-devel

ADD Gemfile /data/
ADD dynflow.gemspec /data/
ADD lib/dynflow/version.rb /data/lib/dynflow/version.rb
WORKDIR /data
RUN bundle install --without mysql

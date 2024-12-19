---
layout: post
title:  "Simple Docker Setup for Ruby development"
---

When forking a project, I like having a simple Docker setup to quickly start.

First, I create a `docker` folder and I add the following files in it:
 - [Dockerfile](#dockerfile)
 - [entrypoint.sh](#entrypointsh)

Then, I add a [docker-compose.yml](#docker-composeyml) in the root folder of the project.
Simply run:

`docker compose run --rm cli <your_bundle_exec_command>`

⚠️ The image will be built only at the first execution and subsequent calls won't automatically rebuild the initial image.
If your making changes along the way you need to add the `--build` option:

`docker compose run --build --rm cli <your_bundle_exec_command>`

# Dockerfile

```dockerfile
ARG RUBY_VERSION=3
FROM ruby:${RUBY_VERSION}-alpine

ENV BUNDLE_PATH /usr/local/bundle/gems
ENV LIB_PATH /var/gem
# --enable-frozen-string-literal maybe not be suitable for all projects 
ENV RUBYOPT --enable-frozen-string-literal --yjit
# taken from dockerfile-rails https://github.com/fly-apps/dockerfile-rails/blob/f34fab26ae3b77a14c15b4bafb0fb91f911b8d8a/lib/generators/dockerfile_generator.rb#L981-L983
ENV LD_PRELOAD libjemalloc.so.2
ENV MALLOC_CONF dirty_decay_ms:1000,narenas:2,background_thread:true

# these packages should cover the basics but you might need more
RUN apk add --update --no-cache make g++ gcc git libc-dev gcompat jemalloc && \
    gem update --system && gem install bundler

WORKDIR $LIB_PATH

COPY /docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
```

# entrypoint.sh
```shell
#!/bin/sh

set -e

# Useful information
echo -e "$(ruby --version)\nrubygems $(gem --version)\n$(bundle version)"
# Can run different gemfiles located in `gemfiles` folder
if [ -z "${GEMFILE}" ]
then
  echo "Running default Gemfile"
else
  export BUNDLE_GEMFILE="./gemfiles/${GEMFILE}.gemfile"
  echo "Running gemfile: ${GEMFILE}"
fi

# Keep gems in the latest possible state
(bundle check || bundle install) && bundle update && exec bundle exec ${@}
```

# docker-compose.yml
```yaml
volumes:
  gems:

x-base: &base
  build:
    context: .
    dockerfile: docker/Dockerfile
    args:
      # you can set a specific version
      - RUBY_VERSION=${RUBY_VERSION:-3}
  stdin_open: true
  tty: true
  volumes:
    - .:/var/gem
    - gems:/usr/local/bundle
# if you have multiple gemfiles (see entrypoint.sh), 
# simply uncomment the following lines and change <gemfile_name>
# environment:
#  GEMFILE: <gemfile_name>

services:
  cli:
    <<: *base
```

If you need to run a server, you can add another service that will run a command and expose a port. Here's a example to with `jekyll` with live reload
```yaml
  server:
    <<: *base
    ports:
      - 4000:4000
    # need to change the host since we're running in Docker
    command: [ 'jekyll', 'serve', '--host', '0.0.0.0', '-l' ]
```

To start the service: `docker compose run --rm --service-ports server`

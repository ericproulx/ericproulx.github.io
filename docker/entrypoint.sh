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

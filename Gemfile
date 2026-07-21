Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}" }

gemspec

gem "gem-release"
# top-level, not the gemspec development group: the release job installs
# without development/test, and bundle exec rake release needs rake
gem "rake"

eval_gemfile("Gemfile.devel") rescue nil

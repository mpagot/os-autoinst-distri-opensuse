export DEBIAN_FRONTEND=noninteractive

sudo apt update \
      && sudo apt install -y libssh2-1 libssh2-1-dev libdbus-1-3 libdbus-1-dev \
      cpanminus libinline-python-perl libtest-most-perl libcode-tidyall-perl libjson-validator-perl

sudo make prepare

# Dependency for the Perl::LanguageServer neede by the VSCode Perl extension
sudo apt install -y libanyevent-perl libclass-refresh-perl \
      libdata-dump-perl libio-aio-perl libjson-perl libmoose-perl libpadwalker-perl \
      libscalar-list-utils-perl libcoro-perl

sudo PERL_MM_USE_DEFAULT=1 cpan Perl::LanguageServer

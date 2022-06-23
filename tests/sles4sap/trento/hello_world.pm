use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use base 'consoletest';
use testapi;
use base 'trento';

use constant TRENTO_AZ_PREFIX => 'openqa-trento';

sub run {
    my ($self, $args) = @_;
    $self->select_serial_terminal;
    record_info('INFO', 'VM name:' . $self->get_vm_name());
    record_info('INFO', 'VM name prefix:' . TRENTO_AZ_PREFIX);
    script_run('docker --version');
    $self->podman_self_check();
    assert_script_run 'echo "Hello World!" > echo.log';
    assert_script_run 'echo "Hello Space!" > "echo\ space.log"';
    assert_script_run 'find . -type f -name "*.log"';
    #    assert_script_run 'notexistingcommandtotriggerafailure';
    upload_logs('echo.log');
    upload_logs('echo space.log');


}

sub post_fail_hook {
    my ($self) = shift;
    # $self->select_serial_terminal;
    #script_run('pwd');
    #script_run('ls -lai');
    #script_run('ls -lai ${HOME}/*.log');
    #script_run('ls -lai ' . GITLAB_CLONE_LOG);
    #if (script_run("! [[ -e " . GITLAB_CLONE_LOG . " ]]")) {
    #    upload_logs(GITLAB_CLONE_LOG);
    #}
    #if (script_run("! [[ -e " . PODMAN_PULL_LOG . " ]]")) {
    #   upload_logs(PODMAN_PULL_LOG);
    #}
    upload_logs('echo.log');
    $self->SUPER::post_fail_hook;
}

1;

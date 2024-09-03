# SUSE's openQA tests
#
# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Helper class for amazon ec2
#
# Maintainer: Clemens Famulla-Conrad <cfamullaconrad@suse.de>, qa-c team <qa-c@suse.de>

package publiccloud::ec2;
use Mojo::Base 'publiccloud::provider';
use Mojo::JSON 'decode_json';
use testapi;
use publiccloud::utils "is_byos";
use publiccloud::aws_client;
use publiccloud::ssh_interactive 'select_host_console';

has ssh_key_pair => undef;
use constant SSH_KEY_PEM => 'QA_SSH_KEY.pem';

sub init {
    my ($self) = @_;
    $self->SUPER::init();
    $self->provider_client(publiccloud::aws_client->new());
    $self->provider_client->init();
}

sub find_img {
    my ($self, $name) = @_;

    $name = $self->prefix . '-' . $name;

    my $out = script_output("aws ec2 describe-images  --filters 'Name=name,Values=$name'");
    if ($out =~ /"ImageId":\s+"([^"]+)"/) {
        return $1;
    }
    return;
}

# Returns true if key is already created in EC2 otherwise tries 10 times to create it and then fails
# If the subroutine manager to create key pair in EC2 it stores it in $self->ssh_key_pair

sub create_keypair {
    my ($self, $prefix) = @_;

    return 1 if (script_run('test -s ' . SSH_KEY_PEM) == 0);

    for my $i (0 .. 9) {
        my $key_name = $prefix . "_" . $i;
        my $cmd = "aws ec2 create-key-pair --key-name '" . $key_name
          . "' --query 'KeyMaterial' --output text > " . SSH_KEY_PEM;
        my $ret = script_run($cmd);
        if (defined($ret) && $ret == 0) {
            assert_script_run('chmod 0400 ' . SSH_KEY_PEM);
            $self->ssh_key_pair($key_name);
            return 1;
        }
    }
    return 0;
}

sub delete_keypair {
    my $self = shift;
    my $name = shift || $self->ssh_key;

    return unless $name;

    assert_script_run("aws ec2 delete-key-pair --key-name " . $name);
    $self->ssh_key(undef);
}

sub upload_img {
    my ($self, $file) = @_;

    die("Create key-pair failed") unless ($self->create_keypair($self->prefix . time));

    # AMI of image to use for helper VM to create/build the image on CSP.
    my $helper_ami_id = get_var('PUBLIC_CLOUD_EC2_UPLOAD_AMI');

    # in case AMI for helper VM is not provided in job settings fallback to predefined hash
    unless (defined($helper_ami_id)) {

        # AMI is region specific also we need to use different AMI's for on-demand/BYOS uploads
        my $ami_id_hash = {
            # suse-sles-15-sp4-byos-v20220915-hvm-ssd-x86_64
            'us-west-1-byos' => 'ami-0cf60a7351ac9f023',
            # suse-sles-15-sp4-v20220915-hvm-ssd-x86_64
            'us-west-1' => 'ami-095b00d1799acbc5d',
            # suse-sles-15-sp4-byos-v20220915-hvm-ssd-x86_64
            'us-west-2-byos' => 'ami-02538b480fd1330ac',
            # suse-sles-15-sp4-v20220915-hvm-ssd-x86_64
            'us-west-2' => 'ami-0fbef12dbf17e9796',
            # suse-sles-15-sp4-byos-v20220915-hvm-ssd-x86_64
            'eu-central-1-byos' => 'ami-01fee8ad5154e745b',
            # suse-sles-15-sp4-v20220915-hvm-ssd-x86_64
            'eu-central-1' => 'ami-0622ab5c21c604604',
            # suse-sles-15-sp4-v20220915-hvm-ssd-arm64
            'eu-central-1-arm64' => 'ami-0f33a69f25295ee23',
            # suse-sles-15-sp4-byos-v20220915-hvm-ssd-arm64
            'eu-central-1-byos-arm64' => 'ami-0fe6d5a106cf46cce',
            # suse-sles-15-sp4-v20220915-hvm-ssd-x86_64
            'eu-west-1' => 'ami-0ddb9fc2019be3eef',
            # suse-sles-15-sp4-byos-v20220915-hvm-ssd-x86_64
            'eu-west-1-byos' => 'ami-0067ff53440565874',
            # suse-sles-15-sp4-v20220915-hvm-ssd-arm64
            'eu-west-1-arm64' => 'ami-06033303bb6c72a35',
            # suse-sles-15-sp4-byos-v20220915-hvm-ssd-arm64
            'eu-west-1-byos-arm64' => 'ami-0e70bccfe7758f9fe',
            # suse-sles-15-sp4-byos-v20220915-hvm-ssd-x86_64
            'us-east-2-byos' => 'ami-00d3e0231db6eeee3',
            # suse-sles-15-sp4-v20220915-hvm-ssd-x86_64
            'us-east-2' => 'ami-0ca19ecee2be612fc',
            # suse-sles-15-sp4-v20220915-hvm-ssd-arm64
            'us-east-1-arm64' => 'ami-05dbc19aca86fdae4',
            # suse-sles-15-sp4-byos-v20220915-hvm-ssd-arm64
            'us-east-1-byos-arm64' => 'ami-0e0756f0108a91de8',
        };

        my $ami_id_key = $self->provider_client->region;
        $ami_id_key .= '-byos' if is_byos();
        $ami_id_key .= '-arm64' if check_var('PUBLIC_CLOUD_ARCH', 'arm64');
        $helper_ami_id = $ami_id_hash->{$ami_id_key} if exists($ami_id_hash->{$ami_id_key});
    }

    die('Unable to detect AMI for helper VM') unless (defined($helper_ami_id));

    my ($img_name) = $file =~ /([^\/]+)$/;
    my $img_arch = get_var('PUBLIC_CLOUD_ARCH', 'x86_64');
    my $sec_group = get_var('PUBLIC_CLOUD_EC2_UPLOAD_SECGROUP');
    my $vpc_subnet = get_var('PUBLIC_CLOUD_EC2_UPLOAD_VPCSUBNET');
    my $instance_type = get_required_var('PUBLIC_CLOUD_EC2_UPLOAD_INSTANCE_TYPE');

    if (!$sec_group) {
        $sec_group = script_output("aws ec2 describe-security-groups --output text "
              . "--region " . $self->provider_client->region . " "
              . "--filters 'Name=group-name,Values=tf-sg' "
              . "--query 'SecurityGroups[0].GroupId'"
        );
        $sec_group = "" if ($sec_group eq "None");
    }
    if (!$vpc_subnet) {
        my $vpc_id = script_output("aws ec2 describe-vpcs --output text "
              . "--region " . $self->provider_client->region . " "
              . "--filters 'Name=tag:Name,Values=tf-vpc' "
              . "--query 'Vpcs[0].VpcId'"
        );
        if ($vpc_id ne "None") {
            # Grab subnet with CidrBlock defined in https://gitlab.suse.de/qac/infra/-/blob/master/aws/tf/main.tf
            $vpc_subnet = script_output("aws ec2 describe-subnets --output text "
                  . "--region " . $self->provider_client->region . " "
                  . "--filters 'Name=vpc-id,Values=$vpc_id' 'Name=cidr-block,Values=10.11.4.0/22' "
                  . "--query 'Subnets[0].SubnetId'"
            );
            $vpc_subnet = "" if ($vpc_subnet eq "None");
        }
    }

    # ec2uploadimg will fail without this file, but we can have it empty
    # because we passing all needed info via params anyway
    assert_script_run('echo " " > /root/.ec2utils.conf');

    assert_script_run("ec2uploadimg --access-id \$AWS_ACCESS_KEY_ID -s \$AWS_SECRET_ACCESS_KEY "
          . "--backing-store ssd "
          . "--grub2 "
          . "--machine '" . $img_arch . "' "
          . "-n '" . $self->prefix . '-' . $img_name . "' "
          . "--virt-type hvm --sriov-support "
          . (is_byos() ? '' : '--use-root-swap ')
          . '--ena-support '
          . "--verbose "
          . "--regions '" . $self->provider_client->region . "' "
          . "--ssh-key-pair '" . $self->ssh_key_pair . "' "
          . "--private-key-file " . SSH_KEY_PEM . " "
          . "-d 'OpenQA upload image' "
          . "--wait-count 3 "
          . "--ec2-ami '" . $helper_ami_id . "' "
          . "--type '" . $instance_type . "' "
          . "--user '" . $self->provider_client->username . "' "
          . "--boot-mode '" . get_var('PUBLIC_CLOUD_EC2_BOOT_MODE', 'uefi-preferred') . "' "
          . ($sec_group ? "--security-group-ids '" . $sec_group . "' " : '')
          . ($vpc_subnet ? "--vpc-subnet-id '" . $vpc_subnet . "' " : '')
          . "'$file'",
        timeout => 60 * 60
    );

    my $ami = $self->find_img($img_name);
    die("Cannot find image after upload!") unless $ami;
    script_run("aws ec2 create-tags --resources $ami --tags Key=pcw_ignore,Value=1") if (check_var('PUBLIC_CLOUD_KEEP_IMG', '1'));
    validate_script_output('aws ec2 describe-images --image-id ' . $ami, sub { /"EnaSupport":\s+true/ });
    record_info('INFO', "AMI: $ami");    # Show the ami-* number, could be useful
}

sub terraform_apply {
    my ($self, %args) = @_;
    $args{confidential_compute} = get_var("PUBLIC_CLOUD_CONFIDENTIAL_VM", 0);
    return $self->SUPER::terraform_apply(%args);
}

sub img_proof {
    my ($self, %args) = @_;

    $args{instance_type} //= 't2.large';
    $args{user} //= 'ec2-user';
    $args{provider} //= 'ec2';
    $args{ssh_private_key_file} //= SSH_KEY_PEM;
    $args{key_name} //= $self->ssh_key;

    return $self->run_img_proof(%args);
}

sub cleanup {
    my ($self, $args) = @_;
    script_run('cd ~/terraform');
    my $instance_id = script_output('terraform output -json | jq -r ".vm_name.value[0]"', proceed_on_failure => 1);
    script_run('cd');

    select_host_console(force => 1);
    if (!check_var('PUBLIC_CLOUD_SLES4SAP', 1) && defined($instance_id)) {
        script_run("aws ec2 get-console-output --instance-id $instance_id | jq -r '.Output' > console.txt");
        upload_logs("console.txt", failok => 1);

        script_run("aws ec2 get-console-screenshot --instance-id $instance_id | jq -r '.ImageData' | base64 --decode > console.jpg");
        upload_logs("console.jpg", failok => 1);
    }
    $self->terraform_destroy() if ($self->terraform_applied);
    $self->delete_keypair();
}

sub describe_instance
{
    my ($self, $instance) = @_;
    my $json_output = decode_json(script_output('aws ec2 describe-instances --filter Name=instance-id,Values=' . $instance->instance_id(), quiet => 1));
    my $i_desc = $json_output->{Reservations}->[0]->{Instances}->[0];
    return $i_desc;
}

sub get_state_from_instance
{
    my ($self, $instance) = @_;
    return $self->describe_instance($instance)->{State}->{Name};
}

sub get_ip_from_instance
{
    my ($self, $instance) = @_;
    return $self->describe_instance($instance)->{PublicIpAddress};
}

sub stop_instance
{
    my ($self, $instance) = @_;
    my $instance_id = $instance->instance_id();
    my $attempts = 60;

    die("Outdated instance object") if ($instance->public_ip ne $self->get_ip_from_instance($instance));

    assert_script_run('aws ec2 stop-instances --instance-ids ' . $instance_id, quiet => 1);

    while ($self->get_state_from_instance($instance) ne 'stopped' && $attempts-- > 0) {
        sleep 5;
    }
    die("Failed to stop instance $instance_id") unless ($attempts > 0);
}

sub start_instance
{
    my ($self, $instance, %args) = @_;
    my $attempts = 60;
    my $instance_id = $instance->instance_id();

    my $i_desc = $self->describe_instance($instance);
    die("Try to start a running instance") if ($i_desc->{State}->{Name} ne 'stopped');

    assert_script_run("aws ec2 start-instances --instance-ids $instance_id", quiet => 1);
    sleep 1;    # give some time to update public_ip
    my $public_ip;
    while (!defined($public_ip) && $attempts-- > 0) {
        $public_ip = $self->get_ip_from_instance($instance);
    }
    die("Unable to get new public IP") unless ($public_ip);
    $instance->public_ip($public_ip);
}

sub change_instance_type
{
    my ($self, $instance, $instance_type) = @_;
    die "Instance type is already $instance_type" if ($self->describe_instance($instance)->{InstanceType} eq $instance_type);
    my $instance_id = $instance->instance_id();
    assert_script_run("aws ec2 modify-instance-attribute --instance-id $instance_id --instance-type '{\"Value\": \"$instance_type\"}'");
    die "Failed to change instance type to $instance_type" if ($self->describe_instance($instance)->{InstanceType} ne $instance_type);
}

sub query_metadata {
    my ($self, $instance, %args) = @_;
    my $ifNum = $args{ifNum};
    my $addrCount = $args{addrCount};

    # Cloud metadata service API is reachable at local destination
    # 169.254.169.254 in case of all public cloud providers.
    my $pc_meta_api_ip = '169.254.169.254';

    my $access_token = $instance->ssh_script_output(qq(curl -sw "\\n" -X PUT http://$pc_meta_api_ip/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds:60"));
    record_info("DEBUG", $access_token);
    my $query_meta_ipv4_cmd = qq(curl -sw "\\n" -H "X-aws-ec2-metadata-token: $access_token" "http://$pc_meta_api_ip/latest/meta-data/local-ipv4");
    my $data = $instance->ssh_script_output($query_meta_ipv4_cmd);

    die("Failed to get data from metadata server") unless length($data);
    return $data;
}

1;

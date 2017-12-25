require 'net/ssh/gateway'
require 'byebug'

BASTION_IP_ADDRESS = "54.191.5.134"
PRIVATE_SERVICE_IP_ADDRESS = "10.0.47.136"
RSA_KEY_PATH = ENV['HOME'] + "/.ssh/mike-aws.pem"
SSH_USER = "ec2-user"

IGNORE_KNOWN_HOST_VALUE = Net::SSH::Verifiers::Null.new


def tunnel_through_bastion(params)
  bastion_port = params[:bastion_ssh_port] || 22
  private_host_ssh_port = params[:private_host_ssh_port] || 22
  gateway = Net::SSH::Gateway.new(params[:bastion_ip_address], params[:ssh_user],
        port: bastion_port,
        key_data: params[:keys],
        keys_only: true,
        forward_agent: true,
        verify_host_key: IGNORE_KNOWN_HOST_VALUE)

  gateway.open(params[:private_host_ip_address], private_host_ssh_port) do |gateway_port|
    ssh_session = gateway.ssh(params[:private_host_ip_address], params[:ssh_user],
          key_data: params[:keys],
          port: private_host_ssh_port,
          keys_only: true,
          verify_host_key: IGNORE_KNOWN_HOST_VALUE)
    yield(ssh_session)
  end
end

rsa_keys = [File.read(RSA_KEY_PATH)]

tunnel_through_bastion(bastion_ip_address: BASTION_IP_ADDRESS,
                private_host_ip_address: PRIVATE_SERVICE_IP_ADDRESS,
                ssh_user: SSH_USER,
                keys: rsa_keys
                ) do |ssh|
  who_am_i = ssh.exec!("whoami")
  host_name = ssh.exec!("echo $HOSTNAME")
  home_directory = ssh.exec!("echo $HOME")
  puts "\nI have tunneled through #{BASTION_IP_ADDRESS} to open an SSH session in #{PRIVATE_SERVICE_IP_ADDRESS}"
  puts "My user name is:      #{who_am_i}"
  puts "I'm logged into host: #{host_name}"
  puts "My home directory is: #{home_directory}\n"
end

#
# == Class: vault::config
#
# Manage basic configuration files and directories for vault.
#
# === Example usage
#
# This class is not called directly.
#
class vault::config {

  if $caller_module_name != $module_name {
    fail("Use of private class ${name} by ${caller_module_name}")
  }

  if $vault::init_style {

    case $vault::init_style {
      'upstart': {
        file { '/etc/init/vault.conf':
          mode    => '0444',
          owner   => 'root',
          group   => 'root',
          content => template('vault/vault.upstart.erb'),
        }
        file { '/etc/init.d/vault':
          ensure => link,
          target => '/lib/init/upstart-job',
          owner  => 'root',
          group  => 'root',
          mode   => '0755',
        }
        $bootstrap_requires = [
          File['/etc/init/vault.conf'],
          File['/etc/init.d/vault'],
        ]
      }
      'systemd': {
        file { '/lib/systemd/system/vault.service':
          mode    => '0444',
          owner   => 'root',
          group   => 'root',
          content => template('vault/vault.systemd.erb'),
        } ~>
        exec { 'vault-systemd-reload':
          command     => '/bin/systemctl daemon-reload',
          refreshonly => true,
        }
        $bootstrap_requires = [
          File['/lib/systemd/system/vault.service'],
          Exec['vault-systemd-reload'],
        ]
      }
      # No templates yet for other init styles, but should be easy enough to
      # add (see the KyleAnderson/consul for a starting point)
#     'sysv': {
#       file { '/etc/init.d/vault':
#         mode    => '0555',
#         owner   => 'root',
#         group   => 'root',
#         content => template('vault/vault.sysv.erb'),
#       }
#     }
#     'debian': {
#       file { '/etc/init.d/vault':
#         mode    => '0555',
#         owner   => 'root',
#         group   => 'root',
#         content => template('vault/vault.debian.erb'),
#       }
#     }
#     'sles': {
#       file { '/etc/init.d/vault':
#         mode    => '0555',
#         owner   => 'root',
#         group   => 'root',
#         content => template('vault/vault.sles.erb'),
#       }
#     }
#     'launchd': {
#       file { '/Library/LaunchDaemons/io.vault.daemon.plist':
#         mode    => '0644',
#         owner   => 'root',
#         group   => 'wheel',
#         content => template('vault/vault.launchd.erb'),
#       }
#     }
      default: {
        fail("I don't know how to create an init script for style ${vault::init_style}")
      }
    }
  }

  file { '/etc/vault':
    ensure => 'directory',
    owner  => $vault::user,
    group  => $vault::group,
    mode   => '0755',
  }

  file { '/etc/vault/ssl':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0700',
  }

  if $vault::bootstrap {

    $local_cidr_block = $vault::advertise_addr ? {
      /:/     => "${vault::advertise_addr}/128",
      default => "${vault::advertise_addr}/32",
    }

    file { '/usr/local/bin/vault-bootstrap':
      source => 'puppet:///modules/vault/vault-bootstrap',
      owner  => 'root',
      group  => 'root',
      mode   => '0700',
    } ->
    exec { 'vault-bootstrap':
      command => "vault-bootstrap --puppet-app-id=${vault::puppet_app_id} --common-name=${vault::common_name} --alt-names=${vault::alt_names_string} --cidr-block=${local_cidr_block} -- ${vault::admins_string}",
      path    => "${::vault::bin_dir}:${::path}",
      unless  => '/usr/bin/test -f /etc/vault/ssl/vault.cert.pem',
      require => flatten([
        File["${::vault::bin_dir}/deploy-ssl-certificate"],
        File["${::vault::bin_dir}/vault-auth-user"],
        File["${::vault::bin_dir}/vault"],
        File['/etc/vault/ssl'],
        File['vault config.hcl'],
        $bootstrap_requires,
      ]),
      before => Service['vault'],
    }
  } else {
    if $vault::tls_cert_file != '/etc/vault/ssl/vault.cert.pem' {
      file { '/etc/vault/ssl/vault.cert.pem':
        ensure => 'file',
        source => $vault::tls_cert_file,
        mode   => '0444',
      }
    }
    if $vault::tls_key_file != '/etc/vault/ssl/vault.key.pem' {
      file { '/etc/vault/ssl/vault.key.pem':
        ensure => 'file',
        source => $vault::tls_key_file,
        mode   => '0400',
      }
    }
  }

  file { 'vault config.hcl':
    ensure  => 'present',
    path    => $vault::config_file,
    content => template('vault/config.hcl.erb'),
  }

}

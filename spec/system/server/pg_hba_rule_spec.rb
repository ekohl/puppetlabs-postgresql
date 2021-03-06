require 'spec_helper_system'

describe 'postgresql::server::pg_hba_rule:' do
  after :all do
    # Cleanup after tests have ran
    puppet_apply("class { 'postgresql::server': ensure => absent }") do |r|
      r.exit_code.should_not == 1
    end
  end

  it 'should create a ruleset in pg_hba.conf' do
    pp = <<-EOS.unindent
      class { 'postgresql::server': }
      postgresql::server::pg_hba_rule { "allow application network to access app database":
        type        => "host",
        database    => "app",
        user        => "app",
        address     => "200.1.2.0/24",
        auth_method => md5,
      }
    EOS

    puppet_apply(pp) do |r|
      r.exit_code.should_not == 1
    end

    puppet_apply(pp) do |r|
      r.exit_code.should be_zero
    end

    shell("grep '200.1.2.0/24' /etc/postgresql/*/*/pg_hba.conf || grep '200.1.2.0/24' /var/lib/pgsql/data/pg_hba.conf") do |r|
      r.exit_code.should be_zero
    end
  end

  it 'should create a ruleset in pg_hba.conf that denies db access to db test1' do
    pp = <<-EOS.unindent
      class { 'postgresql::server': }

      postgresql::server::db { "test1":
        user     => "test1",
        password => postgresql_password('test1', 'test1'),
        grant    => "all",
      }

      postgresql::server::pg_hba_rule { "allow anyone to have access to db test1":
        type        => "local",
        database    => "test1",
        user        => "test1",
        auth_method => reject,
        order       => '001',
      }

      user { "test1":
        shell      => "/bin/bash",
        managehome => true,
      }
    EOS
    puppet_apply(pp) do |r|
      r.exit_code.should_not == 1
    end

    shell('su - test1 -c \'psql -U test1 -c "\q" test1\'') do |r|
      r.exit_code.should == 2
    end
  end

  it 'should fail catalogue if postgresql::server::manage_pga_conf is disabled' do
    pp = <<-EOS.unindent
      class { 'postgresql::server':
        manage_pg_hba_conf => false,
      }
      postgresql::server::pg_hba_rule { 'foo':
        type        => "local",
        database    => "test1",
        user        => "test1",
        auth_method => reject,
        order       => '001',
      }
    EOS
    puppet_apply(pp) do |r|
      r.exit_code.should == 1
    end
  end
end

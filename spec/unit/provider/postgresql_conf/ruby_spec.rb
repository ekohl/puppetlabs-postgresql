# frozen_string_literal: true

require 'spec_helper'
provider_class = Puppet::Type.type(:postgresql_conf).provider(:ruby)

describe provider_class do
  let(:resource) { Puppet::Type.type(:postgresql_conf).new(name: 'foo', key: 'foo', value: 'bar', target: '/tmp/foo.conf') }
  let(:provider) { resource.provider }

  describe 'duplicate keys in postgresql.conf' do
    it 'with empty config' do
      allow(provider_class).to receive(:parse_config).with('/tmp/foo.conf').and_return([])

      provider_class.prefetch({resource.name => resource})

      expect(provider.exists?).to be false
      expect(provider_class).to have_received(:parse_config)
    end

    it 'with existing key' do
      allow(provider_class).to receive(:parse_config).with('/tmp/foo.conf').and_return([{ key: 'foo', value: 'incorrect' }])

      provider_class.prefetch({resource.name => resource})

      expect(provider.exists?).to be true
      expect(provider_class).to have_received(:parse_config)
    end

    it 'raises an exception' do
      expect(provider_class).to receive(:parse_config).with('/tmp/foo.conf').and_return([{ key: 'foo', line: 1 }, { key: 'foo', line: 2 }])

      provider_class.prefetch({resource.name => resource})

      expect { provider.exists? }.to raise_error(Puppet::Error, 'found multiple config items of foo found, please fix this')
    end
  end

  it 'has a method create' do
    expect(provider).to respond_to(:create)
  end

  it 'has a method destroy' do
    expect(provider).to respond_to(:destroy)
  end

  it 'has a method value' do
    expect(provider).to respond_to(:value)
  end

  it 'has a method value=' do
    expect(provider).to respond_to(:value=)
  end

  it 'has a method comment' do
    expect(provider).to respond_to(:comment)
  end

  it 'has a method comment=' do
    expect(provider).to respond_to(:comment=)
  end

  it 'is an instance of the Provider Ruby' do
    expect(provider).to be_an_instance_of Puppet::Type::Postgresql_conf::ProviderRuby
  end
end

# frozen_string_literal: true

# This provider is used to manage postgresql.conf files
# It uses ruby to parse the config file and
# to add, remove or modify settings.
#
# The provider is able to parse postgresql.conf files with the following format:
# key = value # comment

Puppet::Type.type(:postgresql_conf).provide(:ruby) do
  desc 'Set keys, values and comments in a postgresql config file.'
  confine kernel: 'Linux'

  def self.instances(resources = nil)
    return [] unless resources

    filenames = resources.collect { |resource| resource[:target] }.uniq

    configs = filenames.to_h { |filename| [filename, parse_config(filename)] }

    resources.filter_map do |resource|
      next unless resource[:target]

      # TODO: this silently ignores the item was found multiple times
      config = configs[resource[:target]]&.find { |hash| hash[:key] == resource[:key] }
      next unless config

      new(
        ensure: :present,
        name: resource[:name],
        key: resource[:key],
        value: config[:value],
        comment: config[:comment],
      )
    end
  end

  def self.prefetch(resources)
    instances(resources.values).each do |prov|
      if (resource = resources[prov.name])
        resource.provider = prov
      end
    end
  end

  # TODO: implement flush?

  # The function pareses the postgresql.conf and figures out which active settings exist in a config file and returns an array of hashes
  #
  def self.parse_config(filename)
    active_settings = []

    File.open(filename) do |file|
      # regex to match active keys, values and comments
      active_values_regex = %r{^\s*(?<key>[\w.]+)\s*=?\s*(?<value>.*?)(?:\s*#\s*(?<comment>.*))?\s*$}
      # empty array to be filled with hashes
      # iterate the file and construct a hash for every matching/active setting
      # the hash is pushed to the array and the array is returned
      File.foreach(file).with_index do |line, index|
        matches = line.match(active_values_regex)
        if matches
          value = if matches[:value].to_i.to_s == matches[:value]
                    matches[:value].to_i
                  elsif matches[:value].to_f.to_s == matches[:value]
                    matches[:value].to_f
                  else
                    matches[:value].delete("'")
                  end
          active_settings << { line_number: index + 1, key: matches[:key], ensure: 'present', value: value, comment: matches[:comment] }
        end
      end
    end

    Puppet.debug("DEBUG: parse_config Active Settings found in Postgreql config file: #{active_settings}")
    active_settings
  end

  # check, if resource exists in postgresql.conf file
  def exists?
    @property_hash[:ensure] == :present
  end

  # remove resource if exists and is set to absent
  def destroy
    entry_regex = %r{^#{Regex.escape(resource[:key])}\s*=\s*#{Regex.escape(resource[:value])}$}

    File.open(resource[:target]) do |file|
      lines = File.readlines(file)

      lines.delete_if do |entry|
        entry.match?(entry_regex)
      end

      write_config(file, lines)
    end
  end

  # create resource if it does not exists
  def create
    File.open(resource[:target]) do |file|
      lines = File.readlines(file)
      new_line = line(key: resource[:key], value: resource[:value], comment: resource[:comment])

      lines.push(new_line)
      write_config(file, lines)
    end
  end

  # getter - get value of a resource
  def value
    @result[:value]
  end

  # getter - get comment of a resource
  def comment
    @result[:comment]
  end

  # setter - set value of a resource
  def value=(_value)
    File.open(resource[:target]) do |file|
      lines = File.readlines(file)
      active_values_regex = %r{^\s*(?<key>[\w.]+)\s*=?\s*(?<value>.*?)(?:\s*#\s*(?<comment>.*))?\s*$}
      new_line = line(key: resource[:key], value: resource[:value], comment: resource[:comment])

      lines.each_with_index do |line, index|
        matches = line.to_s.match(active_values_regex)
        lines[index] = new_line if matches && (matches[:key] == resource[:key] && matches[:value] != resource[:value])
      end
      write_config(file, lines)
    end
  end

  # setter - set comment of a resource
  def comment=(_comment)
    File.open(resource[:target]) do |file|
      lines = File.readlines(file)
      active_values_regex = %r{^\s*(?<key>[\w.]+)\s*=?\s*(?<value>.*?)(?:\s*#\s*(?<comment>.*))?\s*$}
      new_line = line(key: resource[:key], value: resource[:value], comment: resource[:comment])

      lines.each_with_index do |line, index|
        matches = line.to_s.match(active_values_regex)
        lines[index] = new_line if matches && (matches[:key] == resource[:key] && matches[:comment] != resource[:comment])
      end
      write_config(file, lines)
    end
  end

  private

  # Takes elements for a postgresql.conf configuration line and formats them properly
  #
  # @param [String] key postgresql.conf configuration option
  # @param [String] value the value for the configuration option
  # @param [String] comment optional comment that will be added at the end of the line
  # @return [String] line the whole line for the config file, with \n
  def line(key: '', value: '', comment: nil)
    value = value.to_s if value.is_a?(Numeric)
    dontneedquote = value.match(%r{^(\d+.?\d+|\w+)$})
    dontneedequal = key.match(%r{^(include|include_if_exists)$}i)
    line =  key.downcase # normalize case
    line += dontneedequal ? ' ' : ' = '
    if dontneedquote && !dontneedequal
      line += value
    else
      line += "'#{value}'"
    end
    line += " # #{comment}" unless comment.nil? || comment == :absent
    line += "\n"
    line
  end

  # Deletes an existing header from a parsed postgresql.conf configuration file
  #
  # @param [Array] lines of the parsed postgresql configuration file
  def delete_header(lines)
    header_regex = %r{^# HEADER:.*}
    lines.delete_if do |entry|
      entry.match?(header_regex)
    end
  end

  # Adds a header to a parsed postgresql.conf configuration file, after all other changes are made
  #
  # @param [Array] lines of the parsed postgresql configuration file
  def add_header(lines)
    timestamp = Time.now.strftime('%F %T %z')
    header = ["# HEADER: This file was autogenerated at #{timestamp}\n",
              "# HEADER: by puppet.  While it can still be managed manually, it\n",
              "# HEADER: is definitely not recommended.\n"]
    header + lines
  end

  # This function writes the config file, it removes the old header, adds a new one and writes the file
  #
  # @param [File] the file object of the postgresql configuration file
  # @param [Array] lines of the parsed postgresql configuration file
  def write_config(file, lines)
    lines = add_header(delete_header(lines))
    File.write(file, lines.join)
  end
end

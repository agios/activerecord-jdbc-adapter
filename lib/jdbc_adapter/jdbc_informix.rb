module ::ActiveRecord
  class Base
    after_save :write_lobs

  private
    def write_lobs
      if connection.is_a?(JdbcSpec::Informix)
        self.class.columns.select do |c|
          [:text, :binary].include? c.type
        end.each do |c|
          value = self[c.name]
          value = value.to_yaml if unserializable_attribute?(c.name, c)

          unless value.nil? || (value == '')
            connection.write_large_object(c.type == :binary,
                                          c.name,
                                          self.class.table_name,
                                          self.class.primary_key,
                                          quote_value(id),
                                          value)
          end
        end
      end
    end
  end
end

module ::JdbcSpec
  module ActiveRecordExtensions
    def informix_connection(config)
      config[:port] ||= 9088
      config[:url] ||= "jdbc:informix-sqli://#{config[:host]}:#{config[:port]}/#{config[:database]}:INFORMIXSERVER=#{config[:servername]}"
      config[:driver] = 'com.informix.jdbc.IfxDriver'
      jdbc_connection(config)
    end
  end

  module Informix
    def self.extended(base)
      @@db_major_version = base.select_one("SELECT dbinfo('version', 'major') version FROM systables WHERE tabid = 1")['version'].to_i
    end

    def self.column_selector
      [ /informix/i,
        lambda { |cfg, column| column.extend(::JdbcSpec::Informix::Column) } ]
    end

    def self.adapter_selector
      [ /informix/i,
        lambda { |cfg, adapter| adapter.extend(::JdbcSpec::Informix) } ]
    end

    module Column
    private
      # TODO: Test all Informix column types.
      def simplified_type(field_type)
        if field_type =~ /serial/i
          :primary_key
        else
          super
        end
      end
    end

    # TODO: Look into using sequences instead for the PKs.
    def modify_types(tp)
      tp[:primary_key] = "SERIAL PRIMARY KEY"
      tp[:string]      = { :name => "VARCHAR", :limit => 255 }
      tp[:integer]     = { :name => "INTEGER" }
      tp[:float]       = { :name => "FLOAT" }
      tp[:decimal]     = { :name => "DECIMAL" }
      tp[:datetime]    = { :name => "DATETIME YEAR TO FRACTION(5)" }
      tp[:timestamp]   = { :name => "DATETIME YEAR TO FRACTION(5)" }
      tp[:time]        = { :name => "DATETIME HOUR TO FRACTION(5)" }
      tp[:date]        = { :name => "DATE" }
      tp[:binary]      = { :name => "BYTE" }
      tp[:boolean]     = { :name => "BOOLEAN" }
      tp
    end

    def add_limit_offset!(sql, options)
      if options[:limit]
        limit = "FIRST #{options[:limit]}"
        # SKIP available only in IDS >= 10
        offset = (@@db_major_version >= 10 && options[:offset]?
                  "SKIP #{options[:offset]}" : "")
        sql.sub!(/^select /i, "SELECT #{offset} #{limit} ")
      end
      sql
    end

    # TODO: Add some smart quoting for newlines in string and text fields.
    def quote_string(string)
      string.gsub(/\'/, "''")
    end

    def quote(value, column = nil)
      if column && [:binary, :text].include?(column.type)
        # LOBs are updated separately by an after_save trigger.
        "NULL"
      elsif column && column.type == :date
        "'#{value.mon}/#{value.day}/#{value.year}'"
      else
        super
      end
    end

    def remove_index(table_name, options = {})
      @connection.execute_update("DROP INDEX #{index_name(table_name, options)}")
    end

  private
    def select(sql, name = nil)
      # Informix does not like "= NULL", "!= NULL", or "<> NULL".
      execute(sql.gsub(/(!=|<>)\s*null/i, "IS NOT NULL").gsub(/=\s*null/i, "IS NULL"), name)
    end
  end # module Informix
end # module ::JdbcSpec

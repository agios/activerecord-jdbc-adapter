# NOTE: kindly borrowed from AR 4.0.0 (rc1) - only to be used on AR >= 4.0 !
module ArJdbc
  module PostgreSQL
    class SchemaCreation < ActiveRecord::ConnectionAdapters::AbstractAdapter::SchemaCreation

      private

      def visit_AddColumn(o)
        sql_type = type_to_sql(o.type.to_sym, o.limit, o.precision, o.scale)
        sql = "ADD COLUMN #{quote_column_name(o.name)} #{sql_type}"
        add_column_options!(sql, column_options(o))
      end

      def visit_ColumnDefinition(o)
        sql = super
        if o.primary_key? && o.type == :uuid
          sql << " PRIMARY KEY "
          add_column_options!(sql, column_options(o))
        end
        sql
      end

      def add_column_options!(sql, options)
        if options[:array] || options[:column].try(:array)
          sql << '[]'
        end

        column = options.fetch(:column) { return super }
        if column.type == :uuid && options[:default] =~ /\(\)/
          sql << " DEFAULT #{options[:default]}"
        else
          super
        end
      end

    end
  end
end
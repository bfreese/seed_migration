module SeedMigration
  class SeedFile
    class << self
      def create(seeds_file_path)
        return nil unless permit_create?

        @seeds_file_path = seeds_file_path

        write_prefix
        SeedMigration.registrar.each { |register_entry| write_register_entry(register_entry) }
        write_postfix
        seed_file.close
      end

      private

      def permit_create?
        SeedMigration.update_seeds_file && Rails.env.development?
      end

      def database_specified?
        SeedMigration.connects_to_database.present?
      end

      def reset_pk_sequence?
        !SeedMigration.ignore_ids
      end

      def write_register_entry(register_entry)
        register_entry.model.order('id').each do |instance|
          write_line generate_model_creation_string(instance, register_entry)
        end
        return nil unless reset_pk_sequence?

        write_line "ActiveRecord::Base.connection.reset_pk_sequence!('#{register_entry.model.table_name}')"
      end

      def write_prefix
        seed_file.write <<~HEADER
          # encoding: UTF-8
          # This file is auto-generated from the current content of the database. Instead
          # of editing this file, please use the migrations feature of Seed Migration to
          # incrementally modify your database, and then regenerate this seed file.
          #
          # If you need to create the database on another system, you should be using
          # db:seed, not running all the migrations from scratch. The latter is a flawed
          # and unsustainable approach (the more migrations you'll amass, the slower
          # it'll run and the greater likelihood for issues).
          #
          # It's strongly recommended to check this file into your version control system.

        HEADER


        if database_specified?
          write_line "ActiveRecord::Base.connected_to(database: #{SeedMigration.connects_to_database}) do"
          increase_indent
        end

        write_line 'ActiveRecord::Base.transaction do'
        increase_indent
      end

      def write_postfix
        decrease_indent
        write_line 'end'
        if database_specified?
          decrease_indent
          write_line 'end'
        end
        write_line "SeedMigration::Migrator.bootstrap(#{Migrator.last_migration})"
      end

      def write_line(content)
        seed_file.write <<~CONTENT
          #{''.ljust(@indent * 2)}#{content}

        CONTENT
      end

      def seed_file
        @seed_file ||= begin
          file = File.open(@seeds_file_path, 'w')
          @indent = 0
          file
        end
      end

      def increase_indent
        @indent += 1
      end

      def decrease_indent
        @indent -= 1
      end

      def generate_model_creation_string(instance, register_entry)
        attributes = instance.attributes.select {|key| register_entry.attributes.include?(key) }
        if SeedMigration.ignore_ids
          attributes.delete('id')
        end
        sorted_attributes = {}
        attributes.sort.each do |key, value|
          sorted_attributes[key] = value
        end

        if Rails::VERSION::MAJOR == 3 || defined?(ActiveModel::MassAssignmentSecurity)
          "#{instance.class}.#{create_method}(#{JSON.parse(sorted_attributes.to_json)}, :without_protection => true)"
        else
          "#{instance.class}.#{create_method}(#{JSON.parse(sorted_attributes.to_json)})"
        end
      end

      def create_method
        SeedMigration.use_strict_create? ? 'create!' : 'create'
      end
    end
  end
end
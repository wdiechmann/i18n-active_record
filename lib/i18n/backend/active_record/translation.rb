require 'active_record'

module I18n
  module Backend
    # ActiveRecord model used to store actual translations to the database.
    #
    # This model expects a table like the following to be already set up in
    # your the database:
    #
    #   create_table :translations do |t|
    #     t.integer :ox_id                        # translations 'belongs_to' an ox
    #     t.string :locale
    #     t.string :key
    #     t.string :state, default: 'drafted'     # translations are drafted and not 'found' until cycled into 'production'
    #     t.text   :value
    #     t.text   :interpolations
    #     t.boolean :is_proc, :default => false
    #   end
    #
    # This model supports to named scopes :locale and :lookup. The :locale
    # scope simply adds a condition for a given locale:
    #
    #   I18n::Backend::ActiveRecord::Translation.locale(:en).all
    #   # => all translation records that belong to the :en locale
    #
    # The :lookup scope adds a condition for looking up all translations
    # that either start with the given keys (joined by an optionally given
    # separator or I18n.default_separator) or that exactly have this key.
    #
    #   # with translations present for :"foo.bar" and :"foo.baz"
    #   I18n::Backend::ActiveRecord::Translation.lookup(:foo, 1)
    #   # => an array with both translation records :"foo.bar" and :"foo.baz"
    #
    #   I18n::Backend::ActiveRecord::Translation.lookup([:foo, :bar],1)
    #   I18n::Backend::ActiveRecord::Translation.lookup(:"foo.bar",1)
    #   # => an array with the translation record :"foo.bar"
    #
    # When the StoreProcs module was mixed into this model then Procs will
    # be stored to the database as Ruby code and evaluated when :value is
    # called.
    #
    #   Translation = I18n::Backend::ActiveRecord::Translation
    #   Translation.create \
    #     :ox_id  => 1
    #     :locale => 'en'
    #     :key    => 'foo'
    #     :state  => 'production',
    #     :value  => lambda { |key, options| 'FOO' }
    #   Translation.find_by_locale_and_key('en', 'foo').value
    #   # => 'FOO'
    class ActiveRecord
      class Translation < ::ActiveRecord::Base
        TRUTHY_CHAR = "\001"
        FALSY_CHAR = "\002"

        set_table_name 'translations'
        attr_protected :is_proc, :interpolations

        serialize :value
        serialize :interpolations, Array

        class << self
          def locale(locale)
            scoped(:conditions => { :locale => locale.to_s })
          end

          def lookup(keys, *separator)
            column_name = connection.quote_column_name('key')
            keys = Array(keys).map! { |key| key.to_s }
            state = 'drafted'
            unless separator.empty?
              if separator.class == Hash
                ox_id = separator.fetch(:ox_id,nil)
                state = separator.fetch(:state,state)
              else
                warn "[DEPRECATION] Giving a separator to Translation.lookup is deprecated. " <<
                  "You can change the internal separator by overwriting FLATTEN_SEPARATOR."
              end
            end

            namespace = "#{keys.last}#{I18n::Backend::Flatten::FLATTEN_SEPARATOR}%"
            scoped(:conditions => ["(ox_id=?) AND (state=?) AND (#{column_name} IN (?) OR #{column_name} LIKE ?)", ox_id, state, keys, namespace])
          end

          def available_locales(ox_id=nil, state=nil)
            state=state.nil? ? '' : " AND state='#{state}' "
            Translation.find(:all, :select => 'DISTINCT locale', :conditions => ["ox_id=? ?", ox_id, state]).map { |t| t.locale.to_sym }
          end
        end

        def interpolates?(key)
          self.interpolations.include?(key) if self.interpolations
        end

        def value
          value = read_attribute(:value)
          if is_proc
            Kernel.eval(value)
          elsif value == FALSY_CHAR
            false
          elsif value == TRUTHY_CHAR
            true
          else
            value
          end
        end

        def value=(value)
          if value === false
            value = FALSY_CHAR
          elsif value === true
            value = TRUTHY_CHAR
          end

          write_attribute(:value, value)
        end
      end
    end
  end
end


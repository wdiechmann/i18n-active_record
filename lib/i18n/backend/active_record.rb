require 'i18n/backend/base'
require 'i18n/backend/active_record/translation'

module I18n
  module Backend
    class ActiveRecord
      autoload :Missing,     'i18n/backend/active_record/missing'
      autoload :StoreProcs,  'i18n/backend/active_record/store_procs'
      autoload :Translation, 'i18n/backend/active_record/translation'

      module Implementation
        include Base, Flatten

        def available_locales(ox_id=nil, state=nil)
          begin
            Translation.available_locales(ox_id, state)
          rescue ::ActiveRecord::StatementInvalid
            []
          end
        end

        def store_translations(locale, data, options = {})
          ENV['OX_ID'] ||= nil
          escape = options.fetch(:escape, true)
          state = options.fetch(:state, 'drafted')
          ox_id = options.fetch(:ox_id, ENV['OX_ID'])
          flatten_translations(locale, data, escape, false).each do |key, value|
            Translation.locale(locale).lookup(expand_keys(key), ox_id).delete_all
            Translation.create(:locale => locale.to_s, :key => key.to_s, :value => value, :ox_id => ox_id, state: state )
          end
        end

      protected

        def lookup(locale, key, scope = [], options = {})
          ENV['OX_ID'] ||= nil
          ox_id = options.fetch(:ox_id, ENV['OX_ID'])
          state = options.fetch(:state, 'production')
          key = normalize_flat_keys(locale, key, scope, options[:separator])
          result = Translation.locale(locale).lookup(key,ox_id,state).all

          if result.empty?
            nil
          elsif result.first.key == key
            result.first.value
          else
            chop_range = (key.size + FLATTEN_SEPARATOR.size)..-1
            result = result.inject({}) do |hash, r|
              hash[r.key.slice(chop_range)] = r.value
              hash
            end
            result.deep_symbolize_keys
          end
        end

        # For a key :'foo.bar.baz' return ['foo', 'foo.bar', 'foo.bar.baz']
        def expand_keys(key)
          key.to_s.split(FLATTEN_SEPARATOR).inject([]) do |keys, key|
            keys << [keys.last, key].compact.join(FLATTEN_SEPARATOR)
          end
        end
      end

      include Implementation
    end
  end
end


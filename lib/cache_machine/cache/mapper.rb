module CacheMachine
  module Cache
    require 'cache_machine/cache/collection'
    require 'cache_machine/cache/resource'
    require 'cache_machine/cache/class_timestamp'

    # CacheMachine::Cache::Map.draw do
    #   resource Venue, :timestamp => false do                          # Says what Venue class should be used as a source of ids for map
    #     collection :events, :scopes => :active, :on => :after_save do  # Says what every event should fill the map with venue ids and use callback to reset cache for every venue.
    #       member :upcoming_events                                     # Says what this method also needs to be reset.
    #       members :similar_events, :festivals
    #     end
    #   end
    #
    #   resource Event # Says what Event class should use timestamp on update (same as resource Event :timestamp => true)
    # end

    class Mapper
      DEFAULT_RESOURCE_OPTIONS   = { :timestamp => true,        :scopes => :scoped }
      DEFAULT_COLLECTION_OPTIONS = { :on        => :after_save, :scopes => :scoped }

      attr_reader :cache_resource
      attr_reader :scope

      def initialize(&block)
        change_scope! nil, :root
        instance_eval(&block) if block_given?
      end

      # Defines model as a source of ids for map.
      #
      # @param [Class] model
      # @param [Hash]options
      def resource(model, options = {}, &block)
        scoped :root, :resource do
          @cache_resource = model

          unless @cache_resource.include? CacheMachine::Cache::Resource
            @cache_resource.send :include, CacheMachine::Cache::Resource
          end

          options.reverse_merge! DEFAULT_RESOURCE_OPTIONS

          # Scopes are used for filtering records what we do not want to store in cache-map.
          @cache_resource.cache_scopes |= [*options[:scopes]]

          # Timestamp is used for tracking changes in whole collection (outside any scope).
          if options[:timestamp]
            unless @cache_resource.include? CacheMachine::Cache::ClassTimestamp
              @cache_resource.send(:include, CacheMachine::Cache::ClassTimestamp)
            end
          end

          # Hook on associated collections.
          instance_eval(&block) if block_given?

          # Register model as a cache-resource.
          CacheMachine::Cache::Map.registered_models |= [@cache_resource]
        end
      end

      protected

        # Adds callbacks to fill the map with model ids and uses callback to reset cache for every instance of the model.
        #
        # @param [String, Symbol] collection_name
        # @param [Hash] options
        def collection(collection_name, options = {}, &block)
          reflection = @cache_resource.reflect_on_association(collection_name)
          reflection or raise ArgumentError, "Relation '#{collection_name}' is not set on the class #{@cache_resource}"

          scoped :resource, :collection do
            options.reverse_merge! DEFAULT_COLLECTION_OPTIONS

            collection_klass   = reflection.klass
            collection_members = get_members(&block)

            unless collection_klass.include? CacheMachine::Cache::Collection
              collection_klass.send :include, CacheMachine::Cache::Collection
            end

            collection_klass.register_cache_dependency @cache_resource, collection_name, { :scopes  => options[:scopes],
                                                                                           :members => collection_members,
                                                                                           :on      => options[:on] }
            @cache_resource.cached_collections |= [collection_name]
          end
        end

        # Appends member to the collection.
        #
        # @param [Array<String, Symbol>] member_names
        def member(*member_names)
          scoped :collection, :member do
            @members = (@members || []) | member_names
          end
        end
        alias members member

        # Returns members of collection in scope.
        #
        # @return [Hash]
        def get_members(&block)
          @members = []
          instance_eval(&block) if block_given?
          @members
        end

        # Checks if method can be called from the scope.
        #
        # @param [Symbol] scope
        def validate_scope!(scope)
          raise "#{scope} can not be called in #{@scope} scope" if @scope != scope
        end

        # Changes scope from one to another.
        #
        # @param [Symbol] from
        # @param [Symbol] to
        def change_scope!(from, to)
          validate_scope!(from)
          @scope = to
        end

        # Runs code in the given scope.
        #
        # @param [Symbol] from
        # @param [Symbol] to
        def scoped(from, to)
          change_scope! from, to
          yield
          change_scope! to, from
        end
    end
  end
end

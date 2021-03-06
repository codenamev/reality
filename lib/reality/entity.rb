module Reality
  require_ %w[entity/coercion entity/wikidata_predicates entity/wikipedia_type]
  
  class Entity
    using Refinements
    
    attr_reader :wikipage, :wikidata, :wikidata_id
    attr_reader :values, :wikipedia_type
    
    def initialize(name, wikipage: nil, wikidata: nil, wikidata_id: nil, load: false)
      @name = name
      @wikipage, @wikidata, @wikidata_id = wikipage, wikidata, wikidata_id
      @values = {}
      
      load! if load
      after_load if @wikipage
    end

    def name
      @wikipage ? @wikipage.title : @name
    end

    def inspect
      if @wikipedia_type && @wikipedia_type.symbol
        "#<#{self.class}#{loaded? ? '' : '?'}(#{name}):#{@wikipedia_type.symbol}>"
      else
        "#<#{self.class}#{loaded? ? '' : '?'}(#{name})>"
      end
    end

    def _describe
      load! unless loaded?
      Util::Format.describe(inspect, values.map{|k,v| [k, v.inspect]})
    end

    def describe
      puts _describe
      nil
    end

    def to_s
      name
    end

    def to_s?
      # FIXME: fuuuuuuuu
      "#{name.include?(',') ? '"' + name + '"' : name}#{loaded? ? '' : '?'}"
    end

    def load!
      if @wikidata_id
        @wikidata = Wikidata::Entity.one_by_id(@wikidata_id)
        if @wikidata && @wikidata.en_wikipage
          @wikipage = Infoboxer.wikipedia.get(@wikidata.en_wikipage)
        end
      else
        @wikipage = Infoboxer.wikipedia.get(name)
        @wikidata = if @wikipage
          Wikidata::Entity.one_by_wikititle(@wikipage.title)
        else
          Wikidata::Entity.one_by_label(name)
        end
      end
      after_load
      self
    end

    def setup!(wikipage: nil, wikidata: nil)
      @wikipage, @wikidata = wikipage, wikidata
      after_load if @wikipage || @wikidata
    end

    def loaded?
      !!(@wikipage || @wikidata)
    end

    # Don't try to convert me!
    UNSUPPORTED_METHODS = [:to_hash, :to_ary, :to_a, :to_str, :to_int]

    def method_missing(sym, *arg, **opts, &block)
      if arg.empty? && opts.empty? && !block && sym !~ /[=?!]/ &&
        !UNSUPPORTED_METHODS.include?(sym)
        
        load! unless loaded?

        # now some new method COULD emerge while loading
        if methods.include?(sym)
          send(sym)
        else
          values[sym]
        end
      else
        super
      end
    end

    def respond_to?(sym, include_all = false)
      sym !~ /[=?!]/ && !UNSUPPORTED_METHODS.include?(sym) || super(sym)
    end

    class << self
      def load(name, type = nil)
        Entity.new(name, load: true).tap{|entity|
          return nil if !entity.loaded?
          return nil if type && entity.wikipedia_type != type
        }
      end
    end

    def to_h
      load! unless loaded?
      {name: name}.merge \
        values.map{|k, v| [k.to_sym, Coercion.to_simple_type(v)]}.to_h
    end

    def to_json
      to_h.to_json
    end

    protected

    def after_load
      if @wikipage && !@wikipedia_type
        if (@wikipedia_type = WikipediaType.for(self))
          extend(@wikipedia_type)
        end
      end
      if @wikidata
        @values.update(WikidataPredicates.parse(@wikidata))
      end
      (@values.keys - methods).each do |sym|
        define_singleton_method(sym){@values[sym]}
      end
    end
  end
end

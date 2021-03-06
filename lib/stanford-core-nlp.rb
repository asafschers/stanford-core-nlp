require 'bind-it'
require 'stanford-core-nlp/config'

module StanfordCoreNLP
  extend BindIt::Binding

  # ############################ #
  # BindIt Configuration Options #
  # ############################ #

  # The default path for the JAR files
  # is the gem's bin folder.
  self.jar_path = File.dirname(__FILE__).gsub(/\/lib\z/, '') + '/bin/'

  # Default namespace is the Stanford pipeline namespace.
  self.default_namespace = 'edu.stanford.nlp.pipeline'

  # Load the JVM with a minimum heap size of 512MB,
  # and a maximum heap size of 1024MB.
  StanfordCoreNLP.jvm_args = ['-Xms512M', '-Xmx1024M']

  # Turn logging off by default.
  StanfordCoreNLP.log_file = nil

  # Default JAR files to load.
  StanfordCoreNLP.default_jars = [
    'joda-time.jar',
    'xom.jar',
    'stanford-corenlp.jar',
    'jollyday.jar',
    'bridge.jar'
  ]

  # Default classes to load.
  StanfordCoreNLP.default_classes = [
    ['StanfordCoreNLP', 'edu.stanford.nlp.pipeline', 'CoreNLP'],
    ['Annotation', 'edu.stanford.nlp.pipeline'],
    ['Word', 'edu.stanford.nlp.ling'],
    ['CoreLabel', 'edu.stanford.nlp.ling'],
    ['MaxentTagger', 'edu.stanford.nlp.tagger.maxent'],
    ['CRFClassifier', 'edu.stanford.nlp.ie.crf'],
    ['LexicalizedParser', 'edu.stanford.nlp.parser.lexparser'],
    ['Options', 'edu.stanford.nlp.parser.lexparser'],
    ['Properties', 'java.util'],
    ['ArrayList', 'java.util'],
    ['AnnotationBridge', '']
  ]

  # ########################### #
  # Stanford Core NLP bindings  #
  # ########################### #

  require 'stanford-core-nlp/bridge'
  extend StanfordCoreNLP::Bridge

  class << self
    # The model file names for a given language.
    attr_accessor :model_files
    # The folder in which to look for models.
    attr_accessor :model_path
    # Store the language currently being used.
    attr_accessor :language
    #Custom properties
    attr_accessor :custom_properties
  end

  self.custom_properties = {}

  # The path to the main folder containing the folders
  # with the individual models inside. By default, this
  # is the same as the JAR path.
  self.model_path = self.jar_path

  # ########################### #
  # Public configuration params #
  # ########################### #

  # Use models for a given language. Language can be
  # supplied as full-length, or ISO-639 2 or 3 letter
  # code (e.g. :english, :eng or :en will work).
  def self.use(language)
    lang = nil
    self.model_files = {}
    Config::LanguageCodes.each do |l,codes|
      lang = codes[2] if codes.include?(language)
    end
    self.language = lang
    Config::Models.each do |n, languages|
      models = languages[lang]
      folder = Config::ModelFolders[n]
      if models.is_a?(Hash)
        n = n.to_s
        models.each do |m, file|
          self.model_files["#{n}.#{m}"] = folder + file
        end
      elsif models.is_a?(String)
        self.model_files["#{n}.model"] = folder + models
      end
    end
  end

  # Use english by default.
  self.use :english

  # Set a model file.
  def self.set_model(name, file)
    n = name.split('.')[0].intern
    self.model_files[name] = Config::ModelFolders[n] + file
  end

  # ########################### #
  #    Public API methods       #
  # ########################### #

  def self.bind

    # Take care of Windows users.
    if self.running_on_windows?
      self.jar_path.gsub!('/', '\\')
      self.model_path.gsub!('/', '\\')
    end

    # Make the bindings.
    super

    # Bind annotation bridge.
    self.default_classes.each do |info|
      klass = const_get(info.first)
      self.inject_get_method(klass)
    end

  end

  # Load a StanfordCoreNLP pipeline with the
  # specified JVM flags and StanfordCoreNLP
  # properties.
  def self.load(*annotators)

    self.bind unless self.bound

    # Prepend the JAR path to the model files.
    properties = {}
    self.model_files.each do |k,v|
      found = false
      annotators.each do |annotator|
        found = true if k.index(annotator.to_s)
        break if found
      end
      next unless found
      f = self.model_path + v
      unless File.readable?(f)
        raise "Model file #{f} could not be found. " +
        "You may need to download this file manually " +
        "and/or set paths properly."
      end
      properties[k] = f
    end

    properties['annotators'] = annotators.map { |x| x.to_s }.join(', ')

    unless self.language == :english
      # Bug fix for French/German parsers.
      # Otherwise throws "IllegalArgumentException:
      # Unknown option: -retainTmpSubcategories"
      properties['parse.flags'] = ''
      # Bug fix for French/German parsers.
      # Otherswise throws java.lang.NullPointerException: null.
      properties['parse.buildgraphs'] = 'false'
    end

    # Bug fix for NER system. Otherwise throws:
    # Error initializing binder 1 at edu.stanford.
    # nlp.time.Options.<init>(Options.java:88)
    properties['sutime.binders'] = '0'

    # Manually include SUTime models.
    if annotators.include?(:ner)
      properties['sutime.rules'] =
      self.model_path + 'sutime/defs.sutime.txt, ' +
      self.model_path + 'sutime/english.sutime.txt'
    end

    props = get_properties(properties)

    # Hack for Java7 compatibility.
    bridge = const_get(:AnnotationBridge)
    bridge.getPipelineWithProperties(props)

  end

  # Hack in order not to break backwards compatibility.
  def self.const_missing(const)
    if const == :Text
      puts "WARNING: StanfordCoreNLP::Text has been deprecated." +
      "Please use StanfordCoreNLP::Annotation instead."
      Annotation
    else
      super(const)
    end
  end

  private

  # Create a java.util.Properties object from a hash.
  def self.get_properties(properties)
    properties = properties.merge(self.custom_properties)
    props = Properties.new
    properties.each do |property, value|
      props.set_property(property.to_s, value.to_s)
    end
    props
  end

  # Get a Java ArrayList binding to pass lists
  # of tokens to the Stanford Core NLP process.
  def self.get_list(tokens)
    list = StanfordCoreNLP::ArrayList.new
    tokens.each do |t|
      list.add(Word.new(t.to_s))
    end
    list
  end

  # Returns true if we're running on Windows.
  def self.running_on_windows?
    RUBY_PLATFORM.split("-")[1] == 'mswin32'
  end

  # camel_case which also support dot as separator
  def self.camel_case(s)
    s = s.to_s.gsub(/\/(.?)/) { "::#{$1.upcase}" }
    s.gsub(/(?:^|_|\.)(.)/) { $1.upcase }
  end

end

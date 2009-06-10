# LanugageNegotiation

 #### acceptable languages
 
 class ActionController::AbstractRequest
 
   def self.acceptable_languages
     @acceptable_languages ||=
       ENV['RAILS_ACCEPTABLE_LANGUAGES'].split('|').map {|l| l.to_sym}
   end
 
   def self.acceptable_language?(l)
     l.respond_to?(:to_sym) && acceptable_languages.include?(l.to_sym)
   end
 
 end
 
 #### language preference order
 
 class ActionController::AbstractRequest
 
   def accepts_languages!(language=nil)
     @language_priority= nil
     @accepts_languages= [
         language ? language.to_sym : nil,
         ( cookie = cookies['rails_language'] and l = cookie.first and 
             ActionController::AbstractRequest.acceptable_language?(l) ) ? l.to_sym : nil,
         ( @env['HTTP_ACCEPT_LANGUAGE'] || '' ).split(",").collect {|l|
             lsym= l.split(/;|\-/,2)[0].strip.downcase.to_sym
             ActionController::AbstractRequest.acceptable_language?(lsym) ? lsym : nil
         },
         :no_lang,
         ActionController::AbstractRequest.acceptable_languages
     ].flatten.compact.uniq
   end
 
   def accepts_languages
     @accepts_languages || accepts_languages!
   end
 
   def language_priority
     @language_priority ||= 
         accepts_languages.delete_if{ |l| l == :no_lang }
   end
 
 end
 
 #### store specified language into cookie
 
 class ActionController::Base
 
 #  before_filter :set_language
 #    fails for some unknown reason.
 #  following is a workaround.
 
   def perform_action_with_set_rails_language
     set_rails_language
     perform_action_without_set_rails_language
   end
   alias_method_chain :perform_action, :set_rails_language
 
   def set_rails_language
     rails_language= params[:rails_language]
     if rails_language && ActionController::AbstractRequest.acceptable_language?(rails_language)
       cookies['rails_language']= { :value => rails_language }
       request.accepts_languages!(rails_language)
     end
   end
 end
 
 #### unmemoize
 
 module ActiveSupport::Memoizable
 
   def memoized?(symbol)
     original_method = :"_unmemoized_#{symbol}"
     class_eval <<-EOS, __FILE__, __LINE__
       method_defined?(:#{original_method})
     EOS
   end
 
   def unmemoize(*symbols)
     symbols.each do |symbol|
       original_method = :"_unmemoized_#{symbol}"
       memoized_ivar = MEMOIZED_IVAR.call(symbol)
       class_eval <<-EOS, __FILE__, __LINE__
         raise "Not memoized #{symbol}" if !method_defined?(:#{original_method})
         alias #{symbol} #{original_method}
         undef #{original_method}
       EOS
     end
   end
 
 end
 
 #### to pick language-specific templates
 
 class ActionView::Base
 
 private
 
   def _pick_template_sub(template_file_name, lang)
      lang = ".#{lang}"
      lang = "" if lang == :no_lang
     if template = self.view_paths["#{template_file_name}.#{template_format}#{lang}"]
       return template
     elsif template = self.view_paths["#{template_file_name}#{lang}"]
       return template
     elsif (first_render = @_render_stack.first) && first_render.respond_to?(:format_and_extension)
       m= first_render.format_and_extension.match(/(.*)(\.\w+)?$/)
       template = self.view_paths["#{template_file_name}.#{m[1]}#{lang}#{m[2]}"]
       return template
     end
     if template_format == :js && template = self.view_paths["#{template_file_name}.html#{lang}"]
       @template_format = :html
       return template
     end
     nil
   end
   memoize :_pick_template_sub
 
   unmemoize :_pick_template if memoized? :_pick_template
   def _pick_template(template_path)
     return template_path if template_path.respond_to?(:render)
 
     @extension_regexp_src ||= 
         ActionView::Template.template_handler_extensions.map{ |e| Regexp.escape(e) }.join('|')
     @extension_regexp ||= /^\/?(.*?)(?:\.(#{@extension_regexp_src}))?$/
     template_file_name, template_file_extension = template_path.match(@extension_regexp)
 
     # search for localized version
     if controller && controller.respond_to?(:request)
       controller.request.accepts_languages.each do |lang|
         if template = _pick_template_sub(template_file_name, lang)
           return template
         end
       end
     end
 
     # not found in view_paths
     template = ActionView::Template.new(template_path, view_paths)
     if self.class.warn_cache_misses && logger
       logger.debug "[PERFORMANCE] Rendering a template that was " +
         "not found in view path. Templates outside the view path are " +
         "not cached and result in expensive disk operations. Move this " +
         "file into #{view_paths.join(':')} or add the folder to your " +
         "view path list"
     end
     template
 
   end
 
 end
 
 #### for correct mime-type detection
 
 module ActionView
   class Template
     attr_accessor :language
 
     def initialize(template_path, load_paths = [])
       template_path = template_path.dup
       @base_path, @name, @format, @language, @extension = split(template_path)
       @base_path.to_s.gsub!(/\/$/, '') # Push to split method
       @load_path, @filename = find_full_path(template_path, load_paths)
 
       # Extend with partial super powers
       extend RenderablePartial if @name =~ /^_/
     end
 
     unmemoize :format_and_extension
     def format_and_extension
       (extensions = [format, language, extension].compact.join(".")).blank? ? nil : extensions
     end
     memoize :format_and_extension
 
     unmemoize :path
     def path
       [base_path, [name, format, language, extension].compact.join('.')].compact.join('/')
     end
     memoize :path
 
     unmemoize :path_without_extension
     def path_without_extension
       [base_path, [name, format, language].compact.join('.')].compact.join('/')
     end
     memoize :path_without_extension
 
     unmemoize :path_without_format_and_extension
     def path_without_format_and_extension
       [base_path, name].compact.join('/')
     end
     memoize :path_without_format_and_extension
 
     private
 
       # Returns file split into an array
       #   [base_path, name, format, language, extension]
       def split(file)
         if m = file.match(/^(.*\/)?([^\.]+)(?:\.(\w+)(?:\.(\w+)(?:\.(\w+)(?:\.(\w+))?)?)?)?$/)
           if m[6] # multi part format
             [m[1], m[2], "#{m[3]}.#{m[4]}", m[5], m[6]]
           elsif m[5]
             if ActionController::AbstractRequest.acceptable_language?(m[4])
               [m[1], m[2], m[3], m[4], m[5]]
             else # multi part format
               [m[1], m[2], "#{m[3]}.#{m[4]}", m[5]]
             end
           elsif m[4] # no format
             if valid_extension?(m[4])
               if ActionController::AbstractRequest.acceptable_language?(m[3])
                 [m[1], m[2], nil, m[3], m[4]]
               else # Single format
                 [m[1], m[2], m[3], nil, m[4]]
               end
             else
                 [m[1], m[2], m[3], m[4], nil]
             end
           else
             if valid_extension?(m[3])
               [m[1], m[2], nil, nil, m[3]]
             elsif ActionController::AbstractRequest.acceptable_language?(m[3])
               [m[1], m[2], nil, m[3], nil]
             else
               [m[1], m[2], m[3], nil, nil]
             end
           end
         end
       end
   end
 end
 
 #### for page cache
 
 module ActionController::Caching::Pages
   def cache_page(content = nil, options = nil)
     return unless perform_caching && caching_allowed
 
     path = case options
       when Hash
         url_for(options.merge(
             :only_path => true, 
             :skip_relative_url_root => true, 
             :format => params[:format],
             :rails_language => request.language_priority.first))
       when String
         options
       else
         p= request.path.split('.')
         p.pop if ActionController::AbstractRequest.acceptable_language?(p.last)
         p[0]+= self.class.page_cache_extension if p.count==1
         p << request.language_priority.first
         p.join('.')
     end
 
     self.class.cache_page(content || response.body, path)
   end
 end
 
 #### for action cache
 
 module ActionController::Caching::Actions
   class ActionCachePath
 
     def initialize(controller, options = {}, infer_extension=true)
       if infer_extension and options.is_a? Hash
         request_extension = extract_extension(controller.request)
         options = controller.params.merge(
                   options.reverse_merge(
                       :format => request_extension, 
                       :rails_language => controller.request.language_priority.first))
       end
       path = controller.url_for(options).split('://').last
       if infer_extension
         @extension = request_extension
         add_extension!(path, @extension)
       end
       @path = URI.unescape(path)
     end
 
   private
 
     def add_extension!(path, extension)
       if extension
         p= path.split('.')
         p.insert(-2, extension) unless path =~ /\b#{Regexp.escape(extension)}\b/
         p.join('.')
       end
     end
     
     def extract_extension(request)
       p= request.path.split('.')
       # drop file name
       p.shift
       # drop language
       p.pop if !p.empty? && ActionController::AbstractRequest.acceptable_language?(p.last)
       extension = p.join('.')
 
       # If there's no extension in the path, check request.format
       extension = request.cache_format if extension==""
 
       extension
     end
   end
 end
 
 #### for fragment cache
 
 module ActionController
   module Caching
     module Fragments
       def fragment_cache_key(key)
         ActiveSupport::Cache.expand_cache_key(
               key.is_a?(Hash) ? 
                   url_for(key.reverse_merge(
                            :rails_language=>request.language_priority.first)
                       ).split("://").last :
                   key, 
               :views)
       end
     end
  end
 end

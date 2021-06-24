require 'mini_magick'
require 'json'

module Fastlane
  module Actions

    class Template
      attr_accessor :name
      attr_accessor :width, :height

      attr_accessor :file
      attr_accessor :imageOffset, :imageWidth, :imageBelow, :imageRotation
      attr_accessor :imagePreviousOffset, :imagePreviousWidth, :imagePreviousRotation
      attr_accessor :imageNextOffset, :imageNextWidth, :imageNextRotation
      attr_accessor :textOffsetX, :textOffsetY, :textWidth, :textHeight, :textPadding, :textSize, :textFont
    end

    class Colors
      attr_accessor :text, :background

      def merge(other)
        unless other.text.nil? || other.text.empty?
          self.text = other.text
        end
        unless other.background.nil? || other.background.empty?
          self.background = other.background
        end
      end

      def to_s
        "{ text: #{self.text}, background: #{self.background} }"
      end
    end

    class FramerAction < Action
      def self.run(params)
        source_folder = params[:source_folder]
        output_folder = params[:output_folder]
        template_folder = params[:template_folder]
        list_files = Dir.glob("#{source_folder}/**/*.png").sort
        templates = []
        platform = Actions.lane_context[Actions::SharedValues::PLATFORM_NAME]

        # Read config
        UI.success "Fetching templates from #{template_folder}"
        templates = self.load_templates(template_folder)

        # Process each screen
        UI.success "Processing screenshots from #{source_folder}"
        list_files.each_with_index do |file, index|
          UI.message "Processing #{file} index #{index}"

          template = self.find_template(templates, file, platform)
          if template.nil?
            UI.error "Unable to find template for screenshot #{file}"
            next
          end
          UI.verbose "Using template: #{template.name} (#{template.width}x#{template.height})"

          text = self.find_text(source_folder, file)
          UI.verbose "Using text: #{text}"

          colors = self.find_colors(source_folder, file, template_folder)
          UI.verbose "Using colors: #{colors}"

          output = self.find_output(source_folder, file, output_folder, params[:output_suffix])
          UI.verbose "Saving to: #{output}"

          # # Do the magic
          self.combine(file, template, colors, text, output, list_files, index)

          UI.verbose "Framed screenshot #{output}"
        end

        # Done
        UI.success "All screenshots are now framed!"
      end

      def self.load_templates(template_folder)
        json_file_path = "#{template_folder}/config.json"

        UI.user_error!("Missing Config.json file in template folder") unless File.exist?(json_file_path)

        # Read JSON configuration
        json_file = File.read(json_file_path)
        json_config = JSON.parse(json_file)

        config_default = json_config['default']

        # Detect available templates
        templates = []
        Dir.glob("#{template_folder}/**/*.png") do |file|

          name = File.basename(file, ".png")
          UI.message "Loading template #{name}"

          template = Template.new
          template.file = file
          template.name = name

          # Read template image size
          img = MiniMagick::Image.open(file)
          template.width = img.width
          template.height = img.height
          img.destroy!

          # Get template config
          config_custom = json_config[name]

          if config_custom.nil?
            UI.error "Missing configuration for template #{name}"
            next
          end

          # set image
          template.imageOffset   = (config_custom['image'] && config_custom['image']['offset']) || (config_default['image'] && config_default['image']['offset'])
          template.imageWidth    = (config_custom['image'] && config_custom['image']['width']) || (config_default['image'] && config_default['image']['width'])
          template.imageBelow    = (config_custom['image'] && config_custom['image']['add_below']) || (config_default['image'] && config_default['image']['add_below']) || false
          template.imageRotation = (config_custom['image'] && config_custom['image']['rotation']) || (config_default['image'] && config_default['image']['rotation'])

          # set image back
          template.imagePreviousOffset   = (config_custom['image']['previous'] && config_custom['image']['previous']['offset']) || (config_default['image']['previous'] && config_default['image']['previous']['offset'])
          template.imagePreviousWidth    = (config_custom['image']['previous'] && config_custom['image']['previous']['width']) || (config_default['image']['previous'] && config_default['image']['previous']['width'])
          template.imagePreviousRotation = (config_custom['image']['previous'] && config_custom['image']['previous']['rotation']) || (config_default['image']['previous'] && config_default['image']['previous']['rotation'])

          # set image next
          template.imageNextOffset   = (config_custom['image']['next'] && config_custom['image']['next']['offset']) || (config_default['image']['next'] && config_default['image']['next']['offset'])
          template.imageNextWidth    = (config_custom['image']['next'] && config_custom['image']['next']['width']) || (config_default['image']['next'] && config_default['image']['next']['width'])
          template.imageNextRotation = (config_custom['image']['next'] && config_custom['image']['next']['rotation']) || (config_default['image']['next'] && config_default['image']['next']['rotation'])

          # set font
          template.textFont      = (config_custom['text'] && config_custom['text']['font']) || (config_default['text'] && config_default['text']['font'])
          template.textSize      = (config_custom['text'] && config_custom['text']['size']) || (config_default['text'] && config_default['text']['size'])
          template.textWidth     = (config_custom['text'] && config_custom['text']['width']) || (config_default['text'] && config_default['text']['width'])
          template.textHeight    = (config_custom['text'] && config_custom['text']['height']) || (config_default['text'] && config_default['text']['height'])
          template.textPadding   = (config_custom['text'] && config_custom['text']['padding']) || (config_default['text'] && config_default['text']['padding']) || 0
          template.textOffsetX   = (config_custom['text'] && config_custom['text']['offset_x']) || (config_default['text'] && config_default['text']['offset_x']) || 0
          template.textOffsetY   = (config_custom['text'] && config_custom['text']['offset_y']) || (config_default['text'] && config_default['text']['offset_y']) || 0

          templates << template
        end

        return templates
      end

      def self.find_template(templates, screenshot_file, platform)
        if [:ios, :mac].include? platform
          # Read device name from file
          filename = File.basename(screenshot_file)
          device = filename.slice(0, filename.rindex('-'))
        elsif :android == platform
          # Read device name from path
          folder = File.basename(File.dirname(screenshot_file))
          device = folder.slice(0, folder.rindex('S'))
        else
          UI.error "Unsupported platform"
        end

        # Search template that matches that size
        return templates.find { |template| template.name == device }
      end

      def self.find_text(source_dir, screenshot_file)
        directory = File.dirname(screenshot_file)
        strings_path = File.join(directory, "text.json")

        while directory.start_with?(source_dir) && !File.exist?(strings_path) do
          directory = File.dirname(directory)
          strings_path = File.join(directory, "text.json")
        end

        return nil unless File.exist?(strings_path)

        text = JSON.parse(File.read(strings_path))

        result = text.find { |k, v| File.basename(screenshot_file).upcase.include? k.upcase }
        return result.last if result
      end

      def self.find_colors(source_dir, screenshot_file, colors_dir)

        # Default values
        colors = Colors.new
        colors.text = "#000000"
        colors.background = nil

        # Read values from file
        directory = File.dirname(screenshot_file)
        colors_path = File.join(colors_dir, "colors.json")

        while directory.start_with?(source_dir) && !File.exist?(colors_path) do
          directory = File.dirname(directory)
          colors_path = File.join(directory, "colors.json")
        end

        if File.exist?(colors_path)
          config = JSON.parse(File.read(colors_path))

          # Read default values
          default = Colors.new
          default.text = config['default']['text']
          default.background = config['default']['background']
          colors.merge(default)

          # Read and apply override, if any
          override = config.select { |k, v| File.basename(screenshot_file).upcase.include? k.upcase }.values.map { |value|
            c = Colors.new
            c.text = value['text']
            c.background = value['background']
            c
          }
          unless override.empty?
            colors.merge(override.first)
          end
        end

        return colors
      end

      def self.find_output(source_folder, screenshot_file, output_folder, output_suffix)
        # Prepare file name
        if output_suffix.empty?
          file = File.basename(screenshot_file)
        else
          filename = File.basename(screenshot_file, ".*")
          extention = File.extname(screenshot_file)

          file = filename + output_suffix + extention
        end

        sub_path = File.dirname(screenshot_file).sub(source_folder, "")

        # Prepare file path
        file_path = File.join(File.join(output_folder, sub_path), file)

        # Ensure output dir exist
        folder = File.dirname(file_path)
        self.create_dir_if_not_exists(folder)

        return file_path
      end

      # Magic is HERE
      def self.combine(screenshot_file, template, colors, text, output_file, list_files, index)

        # Get list lenght
        list_lenght = list_files.length()
        
        # Var  images
        screenshot_img_back = nil
        screenshot_img      = nil
        screenshot_img_next = nil

        # Prepare base image
        result_img = MiniMagick::Image.open("#{Framer::ROOT}/assets/background.png")
        result_img.resize "#{template.width}x#{template.height}!" # `!` says it should ignore the ratio

        # Apply background color, if any
        unless colors.background.nil?
          result_img.combine_options do |c|
            c.define "png:color-type=2"
            c.fill "#{colors.background}"
            c.draw "rectangle 0,0,#{template.width},#{template.height}"
          end
        end

        # Get template image
        template_img = MiniMagick::Image.open(template.file)
        
        # Get back screenshot
        unless template.imagePreviousOffset.nil?
          if list_lenght >= index -1 
            screenshot_img_back = MiniMagick::Image.open(list_files[index -1]).auto_orient
            screenshot_img_back.resize "#{template.imagePreviousWidth}x"
            unless template.imagePreviousRotation.nil?
              screenshot_img_back.combine_options do |cmd|
                cmd.background "rgba(255,255,255,0.0)" # transparent
                cmd.rotate(template.imagePreviousRotation.to_f)
              end
            end
          else
            UI.error "Unable to find back screenshot index #{index-1} in #{list_lenght}"
          end
        end

        # Get screenshot image
        screenshot_img = MiniMagick::Image.open(screenshot_file).auto_orient
        
        # Resize screenshot to fit template
        screenshot_img.resize "#{template.imageWidth}x"
        
        # rotate screenshot
        unless template.imageRotation.nil?
          screenshot_img.combine_options do |cmd|
            cmd.background "rgba(255,255,255,0.0)" # transparent
            cmd.rotate(template.imageRotation.to_f)
          end
        end

        # Get next screenshot
        unless template.imageNextOffset.nil?
          if list_lenght >= index + 1 
            image_path = list_files[index+1]
            list_files.each_with_index do |_file, _index|
              if _index === index
                print("file: ", _file, " index ", _index, " my index ", index)
              end
            end
            # print("aqui jovem: ", image_path, " list_lenght ", list_lenght, " index ", index)
            screenshot_img_next = MiniMagick::Image.open(list_files[index]).auto_orient
            screenshot_img_next.resize "#{template.imageNextWidth}x"
            unless template.imageNextRotation.nil?
              screenshot_img_next.combine_options do |cmd|
                cmd.background "rgba(255,255,255,0.0)" # transparent
                cmd.rotate(template.imageNextRotation.to_f)
              end
            end
          else
            UI.error "Unable to find next screenshot index #{index+1} in #{list_lenght}"
          end
        end

        # Put screenshot over template
        if template.imageBelow

          # Screenshot back
          unless screenshot_img_back.nil?
            result_img = result_img.composite(screenshot_img_back) do |c|
              c.compose "Over"
              c.geometry template.imagePreviousOffset.to_s

            end
          end

          # Screenshot first
          result_img = result_img.composite(screenshot_img) do |c|
            c.compose "Over"
            c.geometry template.imageOffset.to_s

          end

          # Screenshot next
          unless screenshot_img_next.nil?
            result_img = result_img.composite(screenshot_img_next) do |c|
              c.compose "Over"
              c.geometry template.imageNextOffset.to_s

            end
          end

          # Template second
          result_img = result_img.composite(template_img) do |c|
            c.compose "Over"
          end

        else

          # Template first
          result_img = result_img.composite(template_img) do |c|
            c.compose "Over"
          end

           # Screenshot back
           unless screenshot_img_back.nil?
            result_img = result_img.composite(screenshot_img_back) do |c|
              c.compose "Over"
              c.geometry template.imagePreviousOffset.to_s

            end
          end

          # Screenshot first
          result_img = result_img.composite(screenshot_img) do |c|
            c.compose "Over"
            c.geometry template.imageOffset.to_s

          end

          # Screenshot next
          unless screenshot_img_next.nil?
            result_img = result_img.composite(screenshot_img_next) do |c|
              c.compose "Over"
              c.geometry template.imageNextOffset.to_s

            end
          end

        end

        # Apply text, if any
        unless text.nil?
          # Clean text string before using it
          text.gsub! '\n', "\n"
          text.gsub!(/(?<!\\)(')/) { |s| "\\#{s}" } # escape unescaped apostrophes with a backslash

          # Create image with text
          text_img = MiniMagick::Image.open("#{Framer::ROOT}/assets/background.png")
          text_img.resize "2732x2732!" # Max space available. `!` says it should ignore the ratio

          text_font = template.textFont.nil? ? "Helvetica" : template.textFont

          text_img.combine_options do |c|
            c.font text_font
            c.pointsize template.textSize.to_s
            c.gravity "NorthWest"
            c.draw "text 0,0 '#{text}'"
            c.fill colors.text.to_s
          end
          text_img.trim # remove white space

          UI.verbose "text requires an area of #{text_img.width}x#{text_img.height}"

          # Scale down to fit space (if needed)
          available_width = (template.textWidth || template_img.width) - template.textPadding * 2
          available_height = template.textHeight

          ratio = available_width.to_f / text_img.width.to_f
          if ratio < 1
            UI.important "Scaling down text to fit in space (ratio: #{ratio.round(3)})"
            text_img.resize "#{available_width}x"
          end
          UI.verbose "text area is now #{text_img.width}x#{text_img.height}"

          # Put text image over template
          offset_x = ((available_width - text_img.width) / 2.0 + template.textPadding).round + template.textOffsetX
          offset_y = ((available_height - text_img.height) / 2.0).round + template.textOffsetY
          UI.verbose "text final offset x: #{offset_x} y: #{offset_y}"

          result_img = result_img.composite(text_img) do |c|
            c.compose "Over"
            c.geometry "+#{offset_x}+#{offset_y}"
          end

          text_img.destroy!
        end

        # Save result
        result_img.format "png"
        result_img.write output_file

        # Cleanup temp files
        result_img.destroy!
        screenshot_img.destroy!
        template_img.destroy!

      end

      def self.create_dir_if_not_exists(path)
        recursive = path.split('/')
        directory = ''
        recursive.each do |sub_directory|
          directory += sub_directory + '/'
          Dir.mkdir(directory) unless (File.directory? directory)
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Create images combining app screenshots to templates to make a nice \'screenshot\' to upload in App Store and Google Play"
      end

      def self.authors
        ["DrAL3X", "AzureRodrigo"]
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :source_folder,
            env_name: "FL_FRAMER_SOURCE_FOLDER",
            description: "Folder that contains screenshots to frame",
            is_string: true,
            default_value: "./fastlane/framer/screens",
            verify_block: proc do |value|
              UI.user_error!("Couldn't find folder at path '#{value}'") unless File.exist?(value)
            end),
          FastlaneCore::ConfigItem.new(key: :template_folder,
            env_name: "FL_FRAMER_TEMPLATE_FOLDER",
            description: "Folder that contains frames",
            is_string: true,
            default_value: "./fastlane/framer/templates",
            verify_block: proc do |value|
              UI.user_error!("Couldn't find folder at path '#{value}'") unless File.exist?(value)
            end),
          FastlaneCore::ConfigItem.new(key: :output_folder,
            env_name: "FL_FRAMER_OUTPUT_FOLDER",
            description: "Folder that will contains framed screenshots",
            is_string: true,
            default_value: "./fastlane/screenshots",
            verify_block: proc do |value|
              UI.user_error!("Couldn't find folder at path '#{value}'") unless File.exist?(value)
            end),
          FastlaneCore::ConfigItem.new(key: :output_suffix,
            env_name: "FL_FRAMER_OUTPUT_FILE_SUFFIX",
            description: "Suffix added to each framed screenshot in the output folder",
            is_string: true,
            default_value: "-framed")
        ]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end

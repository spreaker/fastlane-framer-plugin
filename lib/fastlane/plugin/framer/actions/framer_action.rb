require 'mini_magick'
require 'json'

module Fastlane
  module Actions
    class Template
      attr_accessor :name
      attr_accessor :size

      attr_accessor :file
      attr_accessor :imageOffset, :imageWidth
      attr_accessor :textOffsetX, :textOffsetY, :textWidth, :textHeight, :textPadding, :textSize, :textFont, :textColor
    end

    class FramerAction < Action
      def self.run(params)
        source_folder = params[:source_folder]
        output_folder = params[:output_folder]
        template_folder = params[:template_folder]
        templates = []

        # Read config
        UI.success "Fetching templates from #{template_folder}"
        templates = self.load_templates(template_folder)

        # Process each screen
        UI.success "Processing screenshots from #{source_folder}"
        Dir.glob("#{source_folder}/**/*.png") do |file|
          UI.message "Processing #{file}"

          template = self.find_template(templates, file)
          text = self.find_text(file)
          output = self.find_output(source_folder, file, output_folder, params[:output_suffix])

          if template.nil?
            UI.error "Unable to find template for screenshot #{file}"
            next
          end

          UI.verbose "Using template: #{template.name} (#{template.size})"
          UI.verbose "Using text: #{text}"
          UI.verbose "Saving to: #{output}"

          # Do the magic
          self.combine(file, template, text, output)

          UI.verbose "Framed screenshot #{output}"
        end

        # Done
        UI.success "All screenshots are now framed!"
      end

      def self.load_templates(template_folder)
        json_file_path = "#{template_folder}/Config.json"

        UI.user_error!("Missing Config.json file in template folder") unless File.exist?(json_file_path)

        # Read JSON configuration
        json_file = File.read(json_file_path)
        json_config = JSON.parse(json_file)

        config_default = json_config['default']

        # Detect available templates
        templates = []

        Dir.glob("#{template_folder}/*.png") do |file|

          name = File.basename(file, ".png")
          UI.message "Loading template #{name}"

          template = Template.new
          template.file = file
          template.name = name

          # Read template image size
          img = MiniMagick::Image.open(file)
          template.size = "#{img.width}x#{img.height}"
          img.destroy!

          # Get template config
          config_custom = json_config[name]

          if config_custom.nil?
            UI.error "Missing configuration for template #{name}"
            next
          end

          # Set config
          template.imageOffset  = (config_custom['image'] && config_custom['image']['offset']) || (config_default['image'] && config_default['image']['offset'])
          template.imageWidth   = (config_custom['image'] && config_custom['image']['width']) || (config_default['image'] && config_default['image']['width'])

          template.textColor    = (config_custom['text'] && config_custom['text']['color']) || (config_default['text'] && config_default['text']['color'])
          template.textFont     = (config_custom['text'] && config_custom['text']['font']) || (config_default['text'] && config_default['text']['font'])
          template.textSize     = (config_custom['text'] && config_custom['text']['size']) || (config_default['text'] && config_default['text']['size'])
          template.textWidth    = (config_custom['text'] && config_custom['text']['width']) || (config_default['text'] && config_default['text']['width'])
          template.textHeight   = (config_custom['text'] && config_custom['text']['height']) || (config_default['text'] && config_default['text']['height'])
          template.textPadding  = (config_custom['text'] && config_custom['text']['padding']) || (config_default['text'] && config_default['text']['padding']) || 0
          template.textOffsetX  = (config_custom['text'] && config_custom['text']['offset_x']) || (config_default['text'] && config_default['text']['offset_x']) || 0
          template.textOffsetY  = (config_custom['text'] && config_custom['text']['offset_y']) || (config_default['text'] && config_default['text']['offset_y']) || 0

          templates << template
        end

        return templates
      end

      def self.find_template(templates, screenshot_file)
        # Read screenshot image size
        img = MiniMagick::Image.open(screenshot_file)
        size = "#{img.width}x#{img.height}"
        img.destroy!

        # Search template that matches that size
        return templates.find { |template| template.size == size }
      end

      def self.find_text(screenshot_file)
        directory = File.dirname(screenshot_file)
        strings_path = File.join(directory, "text.json")
        return nil unless File.exist?(strings_path)

        text = JSON.parse(File.read(strings_path))

        result = text.find { |k, v| File.basename(screenshot_file).upcase.include? k.upcase }
        return result.last if result
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
        Dir.mkdir(folder) unless File.exist?(folder)

        return file_path
      end

      def self.combine(screenshot_file, template, text, output_file)
        # Get template image
        template_img = MiniMagick::Image.open(template.file)

        # Get screenshot image
        screenshot_img = MiniMagick::Image.open(screenshot_file)

        # Resize screenshot to fit template
        screenshot_img.resize "#{template.imageWidth}x"

        # Put screenshot over template
        result_img = template_img.composite(screenshot_img) do |c|
          c.compose "Over"
          c.geometry template.imageOffset.to_s
        end

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
            c.gravity "Center"
            c.draw "text 0,0 '#{text}'"
            c.fill template.textColor.to_s
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

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Create images combining app screenshots to templates to make a nice \'screenshot\' to upload in App Store"
      end

      def self.authors
        ["DrAL3X"]
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

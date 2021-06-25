describe Fastlane::Actions::FramerAction do
  describe '#load_templates' do
    it 'stops when Config.json is missing' do
      expect do
        Fastlane::Actions::FramerAction.load_templates('fake')
      end.to raise_error "Missing Config.json file in template folder"
    end

    it 'returns a list of Template objects based on files and config' do
      expect(Fastlane::UI).to receive(:message).with("Loading template iPhone5s")
      expect(Fastlane::UI).to receive(:message).with("Loading template iPadAir")

      result = Fastlane::Actions::FramerAction.load_templates('spec/assets/template2')

      expect(result.count).to be == 2
      expect(result[0].name).to eq("iPhone5s")
      expect(result[0].width).to eq(640)
      expect(result[0].height).to eq(1136)
      expect(result[1].name).to eq("iPadAir")
      expect(result[1].width).to eq(2048)
      expect(result[1].height).to eq(1536)

    end
  end

  describe '#find_template' do
    it 'returns only the template that match by name' do
      right = Fastlane::Actions::Template.new
      right.name = "iPhone5s"
      wrong1 = Fastlane::Actions::Template.new
      wrong1.name = "iPadAir"
      wrong2 = Fastlane::Actions::Template.new
      wrong2.name = "iPhoneXsMax"

      templates = [wrong1, right, wrong2]
      file = "spec/assets/screen2/iPhone5s-demo.png"

      result = Fastlane::Actions::FramerAction.find_template(templates, file, :ios)

      expect(result).to be == right
      expect(result.name).to eq("iPhone5s")
    end

    it 'returns nil if no template is valid for a screenshot' do
      wrong1 = Fastlane::Actions::Template.new
      wrong1.name = "iPadAir"
      wrong2 = Fastlane::Actions::Template.new
      wrong2.name = "iPhoneXsMax"

      templates = [wrong1, wrong2]
      file = "spec/assets/screen2/iPhone5s-demo.png"

      result = Fastlane::Actions::FramerAction.find_template(templates, file, :ios)

      expect(result).to be_nil
    end
  end

  describe '#find_text' do
    it 'returns nil if text.json file is missing' do
      dir = "spec/assets"
      file = "spec/assets/screen2/iPhone5s-demo.png"

      result = Fastlane::Actions::FramerAction.find_text(dir, file)

      expect(result).to be_nil
    end

    it 'returns text from text.json file with keyword from filename' do
      dir = "spec/assets"
      file = "spec/assets/screen+text/iPhone5s-demo.png"

      result = Fastlane::Actions::FramerAction.find_text(dir, file)

      expect(result).to eq("This is the text to write")
    end
  end

  describe '#find_colors' do
    it 'returns default colors if colors.json file is missing' do
      dir = "spec/assets"
      file = "spec/assets/screen2/iPhone5s-demo.png"
      template = "spec/assets/template2/iPhone5s.png"

      result = Fastlane::Actions::FramerAction.find_colors(dir, file, template)

      expect(result.text).to eq("#000000")
      expect(result.background).to be_nil
    end

    it 'returns colors from colors.json file with default values' do
      dir = "spec/assets"
      dir_template = "spec/assets/template2-color"
      file = "spec/assets/screen1/iPhone5s-demo2.png"
      
      result = Fastlane::Actions::FramerAction.find_colors(dir, file, dir_template)

      expect(result.text).to eq("#FFFFFF")
      expect(result.background).to eq("#00FFFF")
    end

    it 'returns colors from colors.json file with customized values' do
      dir = "spec/assets"
      dir_template = "spec/assets/template2-color"
      file = "spec/assets/screen/iPhone5s-demo1.png"

      result = Fastlane::Actions::FramerAction.find_colors(dir, file, dir_template)

      expect(result.text).to eq("#FFFFFF")
      expect(result.background).to eq("#FFFF00")
    end
  end

  describe '#find_output' do
    it 'returns output file path, using screenshot filename and custom suffix' do
      screenshot_folder = "spec/assets/screen+text"
      screenshot = "spec/assets/screen+text/demo.png"
      output_folder = "spec/output"
      suffix = "-framed"

      result = Fastlane::Actions::FramerAction.find_output(screenshot_folder, screenshot, output_folder, suffix)

      expect(result).to eq("spec/output/demo-framed.png")
    end
  end

  describe '#run' do

    Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::PLATFORM_NAME] = :mac

    it 'stops when Config.json is missing' do
      expect do
        Fastlane::Actions::FramerAction.run({
          source_folder: 'spec/assets/screen1',
          template_folder: 'fake'
          })
      end.to raise_error "Missing Config.json file in template folder"
    end

    it 'does nothing with no screenshots' do
      expect(Fastlane::UI).to receive(:success).with("Fetching templates from spec/assets/template1")
      expect(Fastlane::UI).to receive(:success).with("Processing screenshots from fake")
      expect(Fastlane::UI).to receive(:success).with("All screenshots are now framed!")

      Fastlane::Actions::FramerAction.run({
        source_folder: 'fake',
        template_folder: 'spec/assets/template1',
        assets_folder: 'lib/fastlane/plugin/framer/assets'
        })
    end

    it 'should generate an image with just screenshot and template' do
      output_folder = "spec/output"

      Fastlane::Actions::FramerAction.run({
        source_folder: 'spec/assets/screen1',
        template_folder: 'spec/assets/template1',
        output_folder: output_folder,
        output_suffix: '-framed'
        })

      output_file = "#{output_folder}/iPhone5s-demo-framed.png"
      expect(File.exist?(output_file)).to be == true

      # Cleanup
      Dir.glob("#{output_folder}/*.png").each { |filename| File.delete(filename) }
    end

    it 'should generate an image with colored text' do
      output_folder = "spec/output"

      Fastlane::Actions::FramerAction.run({
        source_folder: 'spec/assets/screens+text+colors',
        template_folder: 'spec/assets/template1-color',
        output_folder: output_folder,
        output_suffix: '-framed'
        })

      expect(File.exist?("#{output_folder}/iPhone5s-demo1-framed.png")).to be == true
      expect(File.exist?("#{output_folder}/iPhone5s-demo2-framed.png")).to be == true

      # Cleanup
      Dir.glob("#{output_folder}/*.png").each { |filename| File.delete(filename) }
    end

    it 'should generate all images possible' do
      output_folder = "spec/output"

      Fastlane::Actions::FramerAction.run({
        platform: :ios,
        source_folder: 'spec/assets/screen2',
        template_folder: 'spec/assets/template2',
        assets_folder: 'lib/fastlane/plugin/framer/assets',
        output_folder: output_folder,
        output_suffix: '-framed'
        })

      expect(File.exist?("spec/output/iPhone5s-demo-framed.png")).to be == true
      expect(File.exist?("spec/output/iPadAir-demo-framed.png")).to be == true

      # Cleanup
      Dir.glob("#{output_folder}/*.png").each { |filename| File.delete(filename) }
    end

    it 'should combine screenshot and text to make final image' do
      output_folder = "spec/output"

      Fastlane::Actions::FramerAction.run({
        platform: :ios,
        source_folder: 'spec/assets/screen+text',
        template_folder: 'spec/assets/template1',
        assets_folder: 'lib/fastlane/plugin/framer/assets',
        output_folder: output_folder,
        output_suffix: '-framed'
        })

      output_file = "spec/output/iPhone5s-demo-framed.png"
      expect(File.exist?(output_file)).to be == true

      # Cleanup
      Dir.glob("#{output_folder}/*.png").each { |filename| File.delete(filename) }
    end

    it 'should combine screenshot and text and color to make final image and final image with previous' do
      output_folder = "spec/output"

      Fastlane::Actions::FramerAction.run({
        platform: :ios,
        source_folder: 'spec/assets/screen3',
        template_folder: 'spec/assets/template3-full',
        assets_folder: 'lib/fastlane/plugin/framer/assets',
        output_folder: output_folder,
        output_suffix: '-framed'
        })

      output_file1 = "spec/output/Iphone8-1-Offers-framed.png"
      output_file2 = "spec/output/Iphone8-2-Home-framed.png"
      expect(File.exist?(output_file1)).to be == true
      expect(File.exist?(output_file2)).to be == true

      # Cleanup
      Dir.glob("#{output_folder}/*.png").each { |filename| File.delete(filename) }
    end
  end
end

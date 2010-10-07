require 'spec_helper'

describe CopycopterClient do
  def build_client(config = {})
    config[:logger] ||= FakeLogger.new
    default_config = CopycopterClient::Configuration.new.to_hash
    CopycopterClient::Client.new(default_config.update(config))
  end

  def add_project
    api_key = 'xyz123'
    FakeCopycopterApp.add_project(api_key)
  end

  def build_client_with_project(config = {})
    project = add_project
    config[:api_key] = project.api_key
    build_client(config)
  end

  describe "opening a connection" do
    let(:config) { CopycopterClient::Configuration.new }
    let(:http) { Net::HTTP.new(config.host, config.port) }

    before do
      Net::HTTP.stubs(:new => http)
    end

    it "should timeout when connecting" do
      project = add_project
      client = build_client(:api_key => project.api_key, :http_open_timeout => 4)
      client.download
      http.open_timeout.should == 4
    end

    it "should timeout when reading" do
      project = add_project
      client = build_client(:api_key => project.api_key, :http_read_timeout => 4)
      client.download
      http.read_timeout.should == 4
    end

    it "uses ssl when secure" do
      project = add_project
      client = build_client(:api_key => project.api_key, :secure => true)
      client.download
      http.use_ssl.should == true
    end

    it "doesn't use ssl when insecure" do
      project = add_project
      client = build_client(:api_key => project.api_key, :secure => false)
      client.download
      http.use_ssl.should == false
    end

    it "wraps HTTP errors with ConnectionError" do
      errors = [
        Timeout::Error.new,
        Errno::EINVAL.new,
        Errno::ECONNRESET.new,
        EOFError.new,
        Net::HTTPBadResponse.new,
        Net::HTTPHeaderSyntaxError.new,
        Net::ProtocolError.new
      ]

      errors.each do |original_error|
        http.stubs(:get).raises(original_error)
        client = build_client_with_project
        expect { client.download }.
          to raise_error(CopycopterClient::ConnectionError) { |error|
            error.message.
              should == "#{original_error.class.name}: #{original_error.message}"
          }
      end
    end
  end

  it "downloads published blurbs for an existing project" do
    project = add_project
    project.update({
      'draft' => {
        'key.one'   => "unexpected one",
        'key.three' => "unexpected three"
      },
      'published' => {
        'key.one' => "expected one",
        'key.two' => "expected two"
      }
    })

    blurbs = build_client(:api_key => project.api_key, :public => true).download

    blurbs.should == {
      'key.one' => 'expected one',
      'key.two' => 'expected two'
    }
  end

  it "logs that it performed a download" do
    logger = FakeLogger.new
    client = build_client_with_project(:logger => logger)
    client.download
    logger.should have_entry(:info, "** [Copycopter] Downloaded translations")
  end

  it "downloads draft blurbs for an existing project" do
    project = add_project
    project.update({
      'draft' => {
        'key.one' => "expected one",
        'key.two' => "expected two"
      },
      'published' => {
        'key.one'   => "unexpected one",
        'key.three' => "unexpected three"
      }
    })

    blurbs = build_client(:api_key => project.api_key, :public => false).download

    blurbs.should == {
      'key.one' => 'expected one',
      'key.two' => 'expected two'
    }
  end

  it "uploads defaults for missing blurbs in an existing project" do
    project = add_project

    blurbs = {
      'key.one' => 'expected one',
      'key.two' => 'expected two'
    }

    client = build_client(:api_key => project.api_key, :public => true)
    client.upload(blurbs)

    project.reload.draft.should == blurbs
  end

  it "logs that it performed an upload" do
    logger = FakeLogger.new
    client = build_client_with_project(:logger => logger)
    client.upload({})
    logger.should have_entry(:info, "** [Copycopter] Uploaded missing translations")
  end
end

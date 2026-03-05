# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Fetcher do
  it 'raises NotFoundError when NetLogger responds with *error* text' do
    stub_request(:get, 'https://example.org/cgi-bin/NetLogger/GetUpdates3.php')
      .with(query: { 'ProtocolVersion' => '2.3' })
      .to_return(status: 200, body: String.new('*error - Net gone*'))

    expect {
      described_class.new('example.org').get('GetUpdates3.php', 'ProtocolVersion' => '2.3')
    }.to raise_error(Fetcher::NotFoundError, 'Net gone')
  end
end

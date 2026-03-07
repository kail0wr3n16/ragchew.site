require_relative './backend/net_logger'
require_relative './backend/local_logger'

module Backend
  module_function

  def for_net(net)
    net.ragchew_only_testing_net? ? LocalLogger : NetLogger
  end

  def for_creation(ragchew_only_testing_net:)
    ragchew_only_testing_net ? LocalLogger : NetLogger
  end

  def remote
    NetLogger
  end

  class Logger
    PasswordIncorrectError = Backend::NetLogger::PasswordIncorrectError
    NotAuthorizedError = Backend::NetLogger::NotAuthorizedError
    CouldNotCloseNetError = Backend::NetLogger::CouldNotCloseNetError
    CouldNotCreateNetError = Backend::NetLogger::CouldNotCreateNetError
    CouldNotFindNetAfterCreationError = Backend::NetLogger::CouldNotFindNetAfterCreationError

    def initialize(net_info, user: nil, require_logger_auth: false)
      backend_class = Backend.for_net(net_info.net)
      @backend = backend_class.new(net_info, user:, require_logger_auth:)
    end

    def self.start_logging(net_info, password:, user:)
      backend_class = Backend.for_net(net_info.net)
      backend_class.start_logging(net_info, password:, user:)
    end

    def self.create_net!(ragchew_only_testing_net:, **kwargs)
      backend_class = Backend.for_creation(ragchew_only_testing_net:)
      backend_class.create_net!(**kwargs)
    end

    def method_missing(method_name, *args, **kwargs, &block)
      @backend.public_send(method_name, *args, **kwargs, &block)
    end

    def respond_to_missing?(method_name, include_private = false)
      @backend.respond_to?(method_name, include_private) || super
    end
  end
end

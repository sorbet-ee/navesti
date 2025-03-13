module Navesti
  Thread.abort_on_exception = true  # Forces any thread exceptions to be raised immediately
  @workflows = {}

  ###########################################################################
  #
  # => Method: define
  #
  # => Description:
  #    Defines a new workflow using the DSL. The provided block is evaluated in the
  #    context of a WorkflowDefinition, capturing field mappings, workflow steps,
  #    branching logic, error handling, and the expected data format.
  #
  # => Parameters:
  #    - name: A symbol identifying the workflow (e.g., :wise_openbanking_pisp).
  #    - &block: The block containing DSL definitions for the workflow.
  #
  ###########################################################################
  def self.define(name, &block)
    definition = WorkflowDefinition.new(name)
    definition.instance_eval(&block)
    @workflows[name] = definition
  end

  ###########################################################################
  #
  # => Method: find
  #
  # => Description:
  #    Retrieves a workflow definition by its symbolic name.
  #
  # => Parameters:
  #    - name: The symbolic name of the workflow.
  #
  # => Returns:
  #    The corresponding WorkflowDefinition, or nil if not found.
  #
  ###########################################################################
  def self.find(name)
    @workflows[name]
  end

  ###########################################################################
  #
  # => Method: run
  #
  # => Description:
  #    Executes a defined workflow with the provided initial data.
  #
  # => Parameters:
  #    - name: The symbolic name of the workflow.
  #    - data: A hash containing the initial data for the workflow.
  #
  # => Returns:
  #    The final transformed data after processing.
  #
  ###########################################################################
  def self.run(name, data)
    puts "DEBUG: Starting #{name} workflow"
    workflow = find(name)
    raise "Workflow not found: #{name}" unless workflow
    result = workflow.run(data)
    puts "DEBUG: Workflow #{name} completed with result type: #{result.class}"
    result
  end

  ###########################################################################
  #
  # => Class: WorkflowDefinition
  #
  # => Description:
  #    Represents the configuration for a workflow, including the source type, field
  #    mappings, sequential workflow steps, branch definitions, a global error handler,
  #    and the expected data format (:json or :xml).
  #
  ###########################################################################
  class WorkflowDefinition
    attr_reader :name, :source_type, :mappings, :workflow_steps, :branches, :error_handler, :format

    def initialize(name)
      @name = name
      @mappings = []       # Array storing field mapping definitions.
      @workflow_steps = [] # Array storing sequential steps (checks and actions).
      @branches = {}       # Hash storing branch definitions keyed by attribute.
      @error_handler = nil # Global error handling block.
      @format = :json      # Default data format.
    end

    ###########################################################################
    #
    # => Method: format
    #
    # => Description:
    #    Sets the expected data format for the workflow. Accepts :json or :xml.
    #
    # => Parameters:
    #    - fmt: Symbol indicating the format.
    #
    ###########################################################################
    def format(fmt)
      @format = fmt
    end

    ###########################################################################
    #
    # => Method: source
    #
    # => Description:
    #    Sets the source type for the workflow and yields to define field mappings.
    #
    # => Parameters:
    #    - source_type: Symbol indicating the type of the source data.
    #    - &block: Optional block for defining mappings.
    #
    ###########################################################################
    def source(source_type, &block)
      @source_type = source_type
      instance_eval(&block) if block_given?
    end

    ###########################################################################
    #
    # => Method: map
    #
    # => Description:
    #    Defines a mapping from an internal field to an external field.
    #    Supports an optional transformation function.
    #
    # => Parameters:
    #    - from: Symbol representing the internal field.
    #    - opts: Hash of options, including:
    #         :to => external field name (Symbol or Array for nested mapping)
    #         :transform => a Proc or symbol representing a transformation.
    #
    ###########################################################################
    def map(from, opts = {})
      @mappings << { from: from, to: opts[:to], transform: opts[:transform] }
    end

    ###########################################################################
    #
    # => Method: workflow
    #
    # => Description:
    #    Begins a workflow block that defines the sequence of processing steps.
    #
    # => Parameters:
    #    - &block: Block containing step definitions, validations, branches, etc.
    #
    ###########################################################################
    def workflow(&block)
      instance_eval(&block) if block_given?
    end

    ###########################################################################
    #
    # => Method: check
    #
    # => Description:
    #    Adds a validation check to the workflow. If the block returns false,
    #    the workflow raises an error with the provided message.
    #
    # => Parameters:
    #    - message: A string describing the validation.
    #    - &block: Block that receives data and returns a boolean.
    #
    ###########################################################################
    def check(message, &block)
      @workflow_steps << { type: :check, message: message, block: block }
    end

    ###########################################################################
    #
    # => Method: step
    #
    # => Description:
    #    Adds a processing step to the workflow. The step receives the data hash
    #    and returns a modified hash.
    #
    # => Parameters:
    #    - name: A descriptive name for the step.
    #    - &block: Block that processes the data.
    #
    ###########################################################################
    def step(name, &block)
      @workflow_steps << { type: :step, name: name, block: block }
    end

    ###########################################################################
    #
    # => Method: branch
    #
    # => Description:
    #    Defines conditional branching logic based on the value of a specific attribute.
    #
    # => Parameters:
    #    - attribute: Symbol indicating the attribute to branch on.
    #    - &block: Block that defines branches using the `when` method.
    #
    ###########################################################################
    def branch(attribute, &block)
      branch_builder = BranchBuilder.new(attribute)
      branch_builder.instance_eval(&block)
      @branches[attribute] = branch_builder.branches
    end

    ###########################################################################
    #
    # => Method: on_error
    #
    # => Description:
    #    Sets a global error handler for the workflow. The block receives the error and
    #    the current data context.
    #
    # => Parameters:
    #    - &block: Block to handle errors.
    #
    ###########################################################################
    def on_error(&block)
      @error_handler = block
    end

    ###########################################################################
    #
    # => Method: run
    #
    # => Description:
    #    Executes the workflow by applying field mappings, processing steps,
    #    evaluating branch conditions, and handling errors.
    #
    # => Parameters:
    #    - data: Hash containing the initial data.
    #
    # => Returns:
    #    The transformed data after all processing steps.
    #
    # => Error Handling:
    #    If an error occurs, the on_error block is invoked (if defined), otherwise the error is raised.
    #
    ###########################################################################
    def run(data)
      puts "DEBUG: Workflow #{@name} - Starting execution with data: #{data.keys.inspect}"
      
      begin
        # 1. Field Mappings: Transform internal fields to external fields.
        @mappings.each do |mapping|
          value = data[mapping[:from]]
          # Apply transformation if provided.
          if mapping[:transform]
            if mapping[:transform].is_a?(Proc)
              value = mapping[:transform].call(value)
            else
              value = value.send(mapping[:transform])
            end
          end

          # Support nested mapping if :to is an Array.
          if mapping[:to].is_a?(Array)
            current = data
            mapping[:to].each_with_index do |key, index|
              if index == mapping[:to].size - 1
                current[key] = value
              else
                current[key] ||= {}
                current = current[key]
              end
            end
          else
            data[mapping[:to]] = value
          end
        end

        # 2. Sequential Workflow Steps: Process validations and steps.
        puts "DEBUG: Processing workflow steps (#{@workflow_steps.size} steps total)"
        
        # Process each step with additional safeguards
        @workflow_steps.each_with_index do |step, index|
          begin
            puts "DEBUG: About to execute step #{index+1}/#{@workflow_steps.size}: #{step[:name] || step[:type]}"
            
            case step[:type]
            when :check
              unless step[:block].call(data)
                raise "Validation failed: #{step[:message]}"
              end
            when :step
              returned_data = step[:block].call(data)
              
              # Make sure a step returns something, use the original data if nil returned
              if returned_data.nil?
                puts "WARNING: Step #{step[:name]} returned nil, using previous data"
                # Use the original data
              else
                data = returned_data
              end
            end
            
            puts "DEBUG: Successfully finished step #{index+1}/#{@workflow_steps.size}: #{step[:name] || step[:type]}"
          rescue => step_error
            puts "ERROR in step #{step[:name]}: #{step_error.class}: #{step_error.message}"
            raise step_error # re-raise to be caught by the outer rescue
          end
        end

        # 3. Branching Logic: Execute branch steps based on attribute values.
        @branches.each do |attribute, branch_rules|
          branch_value = data[attribute]
          branch_rules.each do |rule|
            if rule[:value] == branch_value
              rule[:steps].each do |step|
                data = step[:block].call(data)
              end
            end
          end
        end

        puts "DEBUG: All steps processed. Total steps: #{@workflow_steps.size}"
        puts "DEBUG: Workflow #{@name} - All steps completed, returning data"
        puts "DEBUG: Final data keys: #{data.keys.inspect}"
        return data # Explicitly return the data
      rescue => e
        puts "DEBUG: Workflow #{@name} - Error occurred: #{e.class}: #{e.message}"
        # Global error handler: Invoke if defined; otherwise, re-raise the error.
        if @error_handler
          result = @error_handler.call(e, data)
          puts "DEBUG: Workflow #{@name} - Error handler executed, returning: #{result.keys.inspect}"
          return result  # Explicitly return the result from error handler
        else
          puts "DEBUG: Workflow #{@name} - No error handler, re-raising exception"
          raise e
        end
      end
    end
  end

  ###########################################################################
  #
  # => Class: BranchBuilder
  #
  # => Description:
  #    Helper class for constructing branch definitions based on a specific attribute.
  #
  # => Attributes:
  #    - attribute: The attribute to branch on.
  #    - branches: Array of branch definitions (each with a value and steps).
  #
  ###########################################################################
  class BranchBuilder
    attr_reader :attribute, :branches

    def initialize(attribute)
      @attribute = attribute
      @branches = []  # Each branch: { value: ..., steps: [...] }
    end

    ###########################################################################
    #
    # => Method: when
    #
    # => Description:
    #    Defines a branch for a specific attribute value.
    #
    # => Parameters:
    #    - value: The value that triggers this branch.
    #    - &block: Block defining steps within this branch.
    #
    ###########################################################################
    def when(value, &block)
      branch_definition = BranchDefinition.new(value)
      branch_definition.instance_eval(&block)
      @branches << { value: value, steps: branch_definition.steps }
    end
  end

  ###########################################################################
  #
  # => Class: BranchDefinition
  #
  # => Description:
  #    Helper class for defining processing steps within a branch.
  #
  # => Attributes:
  #    - value: The attribute value that this branch applies to.
  #    - steps: Array of processing steps for this branch.
  #
  ###########################################################################
  class BranchDefinition
    attr_reader :value, :steps

    def initialize(value)
      @value = value
      @steps = []
    end

    ###########################################################################
    #
    # => Method: step
    #
    # => Description:
    #    Adds a processing step within the branch.
    #
    # => Parameters:
    #    - name: A descriptive name for the step.
    #    - &block: Block that processes data when this branch is taken.
    #
    ###########################################################################
    def step(name, &block)
      @steps << { name: name, block: block }
    end
  end

  ###########################################################################
  #
  # => Module: ExternalServices
  #
  # => Description:
  #    Provides helper methods for interacting with external APIs using Faraday.
  #    This module supports both JSON and XML-based backends. Specify the desired
  #    format (:json or :xml) in your workflow definition, and these methods will
  #    adopt the appropriate behavior.
  #
  ###########################################################################
  module ExternalServices
    require 'faraday'
    require 'json'
    require 'nokogiri'  # For XML parsing

    ###########################################################################
    #
    # => Method: connection
    #
    # => Description:
    #    Builds and returns a Faraday connection object for a given URL, configuring
    #    the connection based on the specified format.
    #
    # => Parameters:
    #    - url: The base URL for the connection.
    #    - fmt: Symbol indicating the format (:json or :xml). Defaults to :json.
    #
    # => Returns:
    #    A Faraday connection object.
    #
    ###########################################################################
    def self.connection(url, fmt = :json)
      Faraday.new(url: url) do |conn|
        case fmt
        when :json
          conn.request :json  # Encode requests as JSON.
          conn.response :json, parser_options: { symbolize_names: false }  # Parse responses as JSON.
        when :xml
          conn.request :url_encoded  # For XML, we use URL-encoded request body.
          # No default XML middleware is used; we'll parse XML manually.
        else
          conn.request :json
          conn.response :json, parser_options: { symbolize_names: false }
        end
        conn.adapter Faraday.default_adapter
      end
    end

    ###########################################################################
    #
    # => Method: get
    #
    # => Description:
    #    Performs an HTTP GET request to the specified URL with the provided headers,
    #    using the format specified.
    #
    # => Parameters:
    #    - url: The target URL.
    #    - headers: Optional hash of HTTP headers.
    #    - fmt: Symbol indicating the expected response format (:json or :xml). Defaults to :json.
    #
    # => Returns:
    #    Parsed response: a hash for JSON, or a Nokogiri::XML document for XML.
    #
    ###########################################################################
    def self.get(url, headers = {}, fmt = :json)
      conn = connection(url, fmt)
      response = conn.get do |req|
        req.headers.update(headers)
      end
      if fmt == :xml
        Nokogiri::XML(response.body)
      else
        response.body
      end
    end

    ###########################################################################
    #
    # => Method: post
    #
    # => Description:
    #    Performs an HTTP POST request to the specified URL with a payload and headers,
    #    using the format specified.
    #
    # => Parameters:
    #    - url: The target URL.
    #    - body: A hash representing the payload.
    #    - headers: Optional hash of HTTP headers.
    #    - fmt: Symbol indicating the format (:json or :xml). Defaults to :json.
    #
    # => Returns:
    #    Parsed response: a hash for JSON, or a Nokogiri::XML document for XML.
    #
    ###########################################################################
    def self.post(url, body = {}, headers = {}, fmt = :json)
      conn = connection(url, fmt)
      response = conn.post do |req|
        req.headers.update(headers)
        req.body = (fmt == :json ? body.to_json : URI.encode_www_form(body))
      end
      if fmt == :xml
        Nokogiri::XML(response.body)
      else
        response.body
      end
    end

    ###########################################################################
    #
    # => Method: initiate_payment
    #
    # => Description:
    #    Initiates a payment by sending a POST request to an external payments API.
    #    The response format is determined by the workflow's configuration.
    #
    # => Parameters:
    #    - data: Hash containing payment details.
    #    - fmt: Symbol indicating the expected response format (:json or :xml). Defaults to :json.
    #
    # => Returns:
    #    The API response parsed as a hash (for JSON) or Nokogiri::XML (for XML).
    #
    ###########################################################################
    def self.initiate_payment(data, fmt = :json)
      url = "https://api.example.com/payments"  # Replace with actual endpoint.
      headers = { "Authorization" => "Bearer YOUR_API_TOKEN" }
      post(url, data, headers, fmt)
    end

    ###########################################################################
    #
    # => Method: check_payment_status
    #
    # => Description:
    #    Checks the status of a payment order by sending a GET request.
    #
    # => Parameters:
    #    - access_token: The access token for authentication.
    #    - payment_order_id: The ID of the payment order.
    #    - fmt: Symbol indicating the expected format (:json or :xml). Defaults to :json.
    #
    # => Returns:
    #    The payment status, as extracted from the API response.
    #
    ###########################################################################
    def self.check_payment_status(access_token, payment_order_id, fmt = :json)
      url = "https://api.example.com/payments/#{payment_order_id}/status"  # Replace with actual endpoint.
      headers = { "Authorization" => "Bearer #{access_token}" }
      result = get(url, headers, fmt)
      # For JSON, we assume result is a hash; for XML, you may need to extract the status using XPath.
      if fmt == :xml
        # Example: assuming <status> element exists in XML response.
        result.at_xpath("//status")&.content
      else
        result["status"]
      end
    end

    ###########################################################################
    #
    # => Method: log_error
    #
    # => Description:
    #    Logs an error along with the provided context.
    #
    # => Parameters:
    #    - error: The error object.
    #    - context: The data context at the time of the error.
    #
    ###########################################################################
    def self.log_error(error, context)
      puts "Error: #{error.message} | Context: #{context.inspect}"
    end

    ###########################################################################
    #
    # => Method: notify
    #
    # => Description:
    #    Notifies the user or system of a specific event (e.g., a payment failure).
    #
    # => Parameters:
    #    - message: A string containing the notification message.
    #
    ###########################################################################
    def self.notify(message)
      puts "Notification: #{message}"
    end
  end
end
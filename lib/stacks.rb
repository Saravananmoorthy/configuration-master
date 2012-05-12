require "json"
require "base64"
require "aws-sdk"

class Stacks
  TEMPLATES_DIR = "#{File.dirname(__FILE__)}/../templates"

  def initialize(name, variables = {})
    @name = name
    @variables = variables
  end

  def create
    cloud_formation = AWS::CloudFormation.new
    stack = cloud_formation.stacks[@name]
    (puts("the CI environment exists already. Nothing to do") and return) if stack.exists?

    stack = cloud_formation.stacks.create(@name, template, parameters)
    sleep 1 until stack.status == "CREATE_COMPLETE"
    while ((status = stack.status) != "CREATE_COMPLETE")
      raise "error creating stack!".red if status == "ROLLBACK_COMPLETE"
    end
    puts "the CI environment has been provisioned successfully".white
    yield stack if block_given?
  end

  def create_or_update
    cloud_formation = AWS::CloudFormation.new
    stack = cloud_formation.stacks[@name]
    if stack.exists?
      puts "updating production environment with the new version"
      begin
        stack.update :template => template, :parameters => parameters[:parameters]
      rescue Exception => e
        if e.message.eql? "No updates are to be performed."
          puts e.message
          return
        else
          raise
        end
      end
    else
      create
    end
  end

  def delete!
    stack = AWS::CloudFormation.new.stacks[@name]
    (puts "couldn't find stack. Nothing to do" and return) unless stack.exists?

    stack.delete
    puts "shutdown command successful"
  end

  def instances
    stack = AWS::CloudFormation.new.stacks[@name]
    stack_instances = stack.resources.select { |resource| resource.resource_type == "AWS::EC2::Instance" }
    stack_instances.map { |stack_instance| Ops::Instance.new(stack_instance.physical_resource_id) }
  end

  private
  def template
    JSON.parse(File.read("#{TEMPLATES_DIR}/#{@name}.erb"))
  end

  def parameters
    if @variables.has_key? "BootScript"
      @variables["BootScript"] = Base64.encode64(@variables["BootScript"]).strip
    end
    {:parameters => @variables}
  end
end

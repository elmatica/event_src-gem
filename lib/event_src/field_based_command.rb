class EventSrc::FieldBasedCommand
  include ActiveModel::Model
  include ActiveModel::Attributes

  class << self
    def model_attributes(*attributes)
      @model_attributes = attributes
      @event_classes = {}
      attributes.each do |a|
        attribute a
        class_str = "::Events::#{command_class.name}::#{a.to_s.camelize}Changed"
        event_classes[a] = class_str.constantize
      end
    end

    def command_for(command_class)
      @command_class = command_class
      attribute record_attr_name
    end

    def record_attr_name
      @record_attr_name ||= command_class.name.underscore.to_sym
    end

    def from_model(model, attributes)
      attrs = model.attributes.slice(*attributes.map(&:to_s))
        .merge(record_attr_name => model)
      new(attrs)
    end

    def command_class
      unless @command_class
        raise StandardError, "command_for has not been called for: #{self.name}"
      end
      @command_class
    end

    def event_classes
      @event_classes
    end
  end

  attribute :actor_id

  def to_model
    self.attributes[self.class.record_attr_name.to_s]
  end

  def form_method
    to_model.persisted? ? :patch : :post
  end

  def save
    persist(raise_error: false)
  end

  def save!
    persist(raise_error: true)
  end

  def persist(raise_error:)
    success = true
    self.class.command_class.transaction do
      build_events.each do |event|
        if raise_error
          event.save!
          next
        end

        unless event.save
          success = false
          event.errors.each do |key|
            event.errors[key].each do |value|
              errors.add(key, value)
            end
          end
        end
      end
      raise ActiveRecord::Rollback unless success
    end
    success
  end

  def build_events
    model = to_model
    @events ||= self.class.event_classes.reduce([]) do |acc, (key, event_class)|
      value = self.attributes[key.to_s]
      value_present = value != nil
      value_changed = model[key] != value
      if value_present && value_changed
        event = event_class.new(
          key => value,
          actor_id: actor_id,
          organisation: organisation,
        )

        acc << event
      end
      acc
    end
  end
end

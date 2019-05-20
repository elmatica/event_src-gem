# This is the BaseEvent module that all Events should use.
# It defines setters and accessors for the defined `data_attributes`
# After create, it uses the aggregator defined by the consumer to apply changes.
#
# Classes including this module must call self.aggregator=.
module EventSrc::BaseEvent
  extend ActiveSupport::Concern

  included do
    before_validation :preset_aggregate
    before_create :apply_and_persist
    self.table_name = :events
    scope :recent_first, -> { reorder("id DESC") }
    after_initialize do
      self.data ||= {}
    end

    extend ClassMethods
  end

  module ClassMethods
    attr_writer :aggregator
    attr_writer :aggregate_name

    def aggregator
      @aggregator || (raise StandardError, "aggregator has not been set on: #{name}")
    end

    def aggregate_name
      @@aggregate_name || (raise "Events must belong to an aggregate")
    end

    def event_for(relation_name, class_name: nil)
      @@aggregate_name = relation_name
      join_table = :"#{relation_name}_event"
      has_one join_table, foreign_key: :event_id
      has_one relation_name, through: join_table
    end

    # Define attributes to be serialize in the `data` column.
    # It generates setters and getters for those.
    #
    # Example:
    #
    # class MyEvent < EventSrc::BaseEvent
    #   data_attributes :title, :description, :drop_id
    # end
    def data_attributes(*attrs)
      @data_attributes ||= []

      attrs.map(&:to_s).each do |attr|
        @data_attributes << attr unless @data_attributes.include?(attr)

        define_method attr do
          self.data ||= {}
          self.data[attr]
        end

        define_method "#{attr}=" do |arg|
          self.data ||= {}
          self.data[attr] = arg
        end
      end

      @data_attributes
    end
  end

  def aggregate=(model)
    public_send "#{aggregate_name}=", model
  end

  # Return the aggregate that the event will apply to
  def aggregate
    public_send aggregate_name
  end

  def aggregate_id=(id)
    public_send "#{aggregate_name}_id=", id
  end

  def aggregate_id
    public_send "#{aggregate_name}_id"
  end

  def build_aggregate
    aggregate = self.class.reflect_on_association(aggregate_name)
      .klass.new
    send(:"#{aggregate_name}=", aggregate)
  end

  delegate :aggregate_name, to: :class

  # Underscored class name by default. ex: "post/updated"
  # Used when sending events to the data pipeline
  def self.event_name
    self.name.sub("Events::", "").underscore
  end

  private

  def preset_aggregate
    # Build aggregate when the event is creating an aggregate
    self.aggregate ||= build_aggregate
  end

  # Apply the transformation to the aggregate and save it.
  def apply_and_persist
    # Lock! (all good, we're in the ActiveRecord callback chain transaction)
    aggregate.lock! if aggregate.persisted?

    apply
  end

  def apply
    self.class.aggregator.call(aggregate, self)
  end
end

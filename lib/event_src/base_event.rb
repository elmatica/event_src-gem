# This is the BaseEvent class that all Events inherit from.
# It defines setters and accessors for the defined `data_attributes`
# After create, it uses the sub classes aggregator to apply changes.
#
# Subclasses must call self.aggregator=.
class EventSrc::BaseEvent < ActiveRecord::Base
  before_validation :preset_aggregate
  before_create :apply_and_persist

  self.abstract_class = true

  scope :recent_first, -> { reorder("id DESC") }

  class << self
    attr_writer :aggregator

    def aggregator
      @aggregator || (raise StandardError, "aggregator has not been set on: #{name}")
    end
  end

  after_initialize do
    self.data ||= {}
  end

  # Define attributes to be serialize in the `data` column.
  # It generates setters and getters for those.
  #
  # Example:
  #
  # class MyEvent < EventSrc::BaseEvent
  #   data_attributes :title, :description, :drop_id
  # end
  def self.data_attributes(*attrs)
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
    public_send "build_#{aggregate_name}"
  end

  def self.aggregate_name
    inferred_aggregate = reflect_on_all_associations(:belongs_to).first
    raise "Events must belong to an aggregate" if inferred_aggregate.nil?
    inferred_aggregate.name
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

    # Persist!
    aggregate.save!
    self.aggregate_id = aggregate.id if aggregate_id.nil?
  end

  def apply
    self.class.aggregator.call(aggregate, self)
  end
end

module ValueChanged
  def changed?(model, field, new_val)
    current = model[field]
    model[field] = new_val
    model.changed_attributes.include?(field)
  ensure
    model[field] = current
  end

  module_function :changed?
end

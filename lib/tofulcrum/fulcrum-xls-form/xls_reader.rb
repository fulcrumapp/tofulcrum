module Fulcrum
  class XlsReader
    VALID_ROW_TYPES = [
      'section begin',
      'section end',
      'text',
      'choice',
      'yesno',
      'numeric',
      'repeatable begin',
      'repeatable end',
      'date',
      'time',
      'address',
      'signature',
      'photos',
      'label'
    ]

    def self.read(file)
      spreadsheet = Roo::Spreadsheet.open(file)

      parse_metadata(spreadsheet)
      parse_status_field(spreadsheet)
      parse_choices(spreadsheet)
      parse_schema(spreadsheet)
    end

    def self.parse_schema(spreadsheet)
      form = { form: { name: @metadata['name'],
                       description: @metadata['description'],
                       status_field: @status_field,
                       elements: make_elements(make_hash(spreadsheet.sheet('form'))) } }

      puts form.to_json
    end

    def self.make_elements(rows)
      root = { elements: [] }

      containers = [ root ]

      current_container = root

      rows.each do |row|
        row = row.with_indifferent_access

        row_type = row['type'].to_s.downcase.strip

        raise "Invalid row type #{row_type}." unless VALID_ROW_TYPES.include?(row_type)

        if !['repeatable end', 'section end'].include?(row_type)
          element = make_element(row, current_container)
          current_container[:elements] << element
        end

        case row_type
        when 'section begin'
          containers << element
          current_container = element

        when 'section end'
          raise "section end found without matching begin" if containers.count == 1

          containers = containers[0..-2]
          current_container = containers.last

        when 'repeatable begin'
          containers << element
          current_container = element

        when 'repeatable end'
          raise "repeatable end found without matching begin" if containers.count == 1

          containers = containers[0..-2]
          current_container = containers.last

        end
      end

      raise "Unmatched sections or repeatables found. The open fields are: #{containers.map {|c| c[:label]}.join(', ')}" if containers.count != 1

      root[:elements]
    end

    def self.make_element(row, container)
      {}.tap do |hash|
        hash[:type] = element_type_for_type(row[:type])
        hash[:label] = row[:label]
        hash[:data_name] = make_data_name(row, container)
        hash[:description] = row[:description]
        hash[:required] = boolean_value(row[:required])
        hash[:hidden] = boolean_value(row[:hidden])
        hash[:disabled] = boolean_value(row[:disabled])
        hash[:numeric] = true if row[:type] == 'numeric'
        hash[:elements] = [] if %w(Section Repeatable).include?(hash[:type])
        hash[:key] = SecureRandom.hex(2)

        case hash[:type]
        when 'Section'
          hash[:display] = row['display'] == 'drilldown' ? 'drilldown' : 'inline'
        when 'ChoiceField'
          hash[:choices] = @choices[row['choices']] if hash[:type] == 'ChoiceField'
          hash[:allow_other] = boolean_value(row[:allow_other])
        when 'YesNoField'
          positive = { label: 'Yes', value: 'yes' }
          negative = { label: 'No',  value: 'no'  }
          neutral  = { label: 'N/A', value: 'n/a' }

          positive[:label] = positive[:value] = row['positive'] if row['positive'].present?
          negative[:label] = negative[:value] = row['negative'] if row['negative'].present?
          neutral[:label] = neutral[:value] = row['neutral'] if row['neutral'].present?

          hash[:positive] = positive
          hash[:negative] = negative
          hash[:neutral]  = neutral
          hash[:neutral_enabled] = row['neutral'].present?
        when 'AddressField'
          hash[:auto_populate] = boolean_value(row[:auto_populate], true)
        end
      end
    end

    def self.make_data_name(row, container)
      return row[:data_name] if row[:data_name]

      if container[:data_name].present?
        "#{container[:data_name]}_#{row[:label].to_s.downcase.parameterize.underscore}"
      else
        row[:label].to_s.downcase.parameterize.underscore
      end
    end

    def self.element_type_for_type(type)
      case type
      when 'section begin'    then 'Section'
      when 'text'             then 'TextField'
      when 'choice'           then 'ChoiceField'
      when 'yesno'            then 'YesNoField'
      when 'numeric'          then 'TextField'
      when 'repeatable begin' then 'Repeatable'
      when 'date'             then 'DateTimeField'
      when 'time'             then 'TimeField'
      when 'address'          then 'AddressField'
      when 'signature'        then 'SignatureField'
      when 'photos'           then 'PhotoField'
      when 'label'            then 'Label'
      else nil
      end
    end

    def self.parse_metadata(spreadsheet)
      sheet = spreadsheet.sheet('metadata')

      raise "Can't find metadata sheet." unless sheet

      metadata = make_hash(sheet)

      @metadata = {}

      metadata.each do |row|
        @metadata[row['key']] = row['value']
      end
    end

    def self.parse_choices(spreadsheet)
      sheet = spreadsheet.sheet('choices')

      return unless sheet

      all_choices = make_hash(sheet)

      @choices = {}

      all_choices.each do |choice|
        @choices[choice['list']] ||= []
        @choices[choice['list']] << choice.slice('label', 'value')
      end
    end

    def self.parse_status_field(spreadsheet)
      sheet = spreadsheet.sheet('status')

      return unless sheet

      statuses = make_hash(sheet)

      @status_field = {}
      @status_field[:label] = @metadata['status_label']
      @status_field[:description] = @metadata['status_description']
      @status_field[:data_name] = @metadata['status_data_name']
      @status_field[:default_value] = @metadata['status_default_value']
      @status_field[:hidden] = boolean_value(@metadata['status_hidden'])
      @status_field[:read_only] = boolean_value(@metadata['status_read_only'])
      @status_field[:enabled] = boolean_value(@metadata['status_enabled'])

      statuses.each do |status|
        @status_field[:choices] ||= []
        @status_field[:choices] << { label: status['label'] || '',
                                     value: status['value'] || status['label'] || '',
                                     color: status_color(status['color']) }
      end
    end

    def self.boolean_value(value, default=false)
      return default if value.nil?
      return %(true yes 1).include?(value.to_s.downcase.strip)
    end

    def self.status_color(human_name)
      case human_name.to_s.strip.downcase
      when 'black'      then '#242424'
      when 'gray'       then '#B3B3B3'
      when 'white'      then '#FFFFFF'
      when 'brown'      then '#704B10'
      when 'pink'       then '#DA0796'
      when 'red'        then '#CB0D0C'
      when 'orange'     then '#FF8819'
      when 'yellow'     then '#FFD300'
      when 'green'      then '#87D30F'
      when 'dark green' then '#2D5D00'
      when 'dark blue'  then '#294184'
      when 'blue'       then '#1891C9'
      else '#CB0D0C'
      end
    end

    def self.make_hash(sheet)
      column_names = []

      sheet.row(1).to_a.each_with_index do |column_name, index|
        column_names << {name: column_name, index: index} if column_name.present?
      end

      rows = []

      sheet.each_with_index do |item, index|
        next if index == 0

        hash = {}

        column_names.each do |column|
          hash[column[:name]] = item[column[:index]]
        end

        rows << hash
      end

      rows
    end
  end
end

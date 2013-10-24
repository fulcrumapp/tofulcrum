require "tofulcrum/version"
require 'csv'
require 'fulcrum'
require 'thor'

module Tofulcrum
  class CLI < Thor
    desc "import", "Import a CSV into a Fulcrum app"
    def import(file, form_id, api_key, mapping=nil)

      Fulcrum::Api.configure do |config|
        config.uri = 'https://api.fulcrumapp.com/api/v2'
        config.key = api_key
      end

      row_index = 0
      upload_index = 0

      lat_index = nil
      lon_index = nil
      column_mapping = []
      records = []

      CSV.foreach(file) do |row|
        is_header = row_index == 0

        if is_header
          lat_index, lon_index = *find_geo_columns(row).compact
          raise 'Unable to find latitude/longitude columns' unless lat_index && lon_index

          lat_name = row[lat_index]
          lon_name = row[lon_index]

          headers = row.clone
          headers.delete_if {|v| [lat_name, lon_name].include?(v)}

          column_mapping = find_mapping_columns(form_id, headers, row, mapping)
        else
          form_values = {}

          column_mapping.each do |map|
            value = nil

            case map[:field]['type']
            when 'ChoiceField'
              value = { choice_values: row[map[:index]].split(',') }
            else
              value = row[map[:index]]
            end

            form_values[map[:field]['key']] = value
          end

          record = {
            record: {
              form_id: form_id,
              latitude: row[lat_index].to_f,
              longitude: row[lon_index].to_f,
              form_values: form_values
            }
          }

          records << record
        end

        row_index += 1
      end

      thread_count = 8

      mutex = Mutex.new

      thread_count.times.map {
        Thread.new(records) do |recs|
          while record = mutex.synchronize { recs.pop }
            Fulcrum::Record.create(record)
            mutex.synchronize {
              print "#{upload_index.to_s.rjust(10, ' ')} records uploaded\r"
              upload_index += 1
            }
          end
        end
      }.each(&:join)
    end

    no_tasks do
      def flatten_elements(elements)
        [].tap do |all|
          elements.each do |element|
            all << element
            all += flatten_elements(element['elements']) if element['elements']
          end
        end
      end

      def find_mapping_columns(form_id, headers, full_row, mapping)
        form = Fulcrum::Form.find(form_id, {})['form']

        elements = flatten_elements(form['elements'])

        if mapping.nil?
          mapping = headers.map {|h| "#{h}=#{h}"}.join(',')
        end

        [].tap do |map|
          mapping.split(',').each do |pair|
            source, dest = *pair.split('=').map(&:strip)

            source_index = full_row.index {|h| h.downcase == source.downcase} rescue nil
            dest_field = elements.find {|e| e['data_name'].downcase == dest.downcase} rescue nil

            raise "Unable to map column #{source} to form field #{dest}." unless source_index && dest_field

            map << { index: source_index, field: dest_field }
          end
        end
      end

      def find_geo_columns(headers)
        lat_columns = ['lat', 'latitude', 'y']
        lon_columns = ['lon', 'long', 'longitude', 'x']
        [headers.index {|h| lat_columns.include?(h.downcase)}, headers.index {|h| lon_columns.include?(h.downcase)}]
      end
    end
  end
end

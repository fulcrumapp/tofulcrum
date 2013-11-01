require 'tofulcrum/version'
require 'csv'
require 'fulcrum'
require 'thor'
require 'securerandom'

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

      column_mapping = []
      records = []
      system_columns = {}

      CSV.foreach(file) do |row|
        is_header = row_index == 0

        if is_header
          system_columns = find_system_columns(row)
          raise 'Unable to find latitude/longitude columns' unless system_columns[:latitude] && system_columns[:longitude]

          user_cols = user_columns(row, system_columns)

          column_mapping = find_mapping_columns(form_id, user_cols, row, mapping)
        else
          form_values = {}

          column_mapping.each do |map|
            value = nil

            case map[:field]['type']
            when 'ChoiceField'
              value = { choice_values: row[map[:index]].split(',').map(&:strip) } rescue nil
            when 'PhotoField'
              value = []
              row[map[:index]].split(',').map(&:strip).each do |photo|
                key = SecureRandom.uuid
                Fulcrum::Photo.create(File.open(photo), "image/jpeg", key, "")
                value << { "photo_id" => key }
              end
            else
              value = row[map[:index]]
            end

            form_values[map[:field]['key']] = value if value
          end

          record = {
            record: {
              form_id: form_id,
              form_values: form_values
            }
          }

          system_columns.each do |attr, index|
            record[:record][attr] = row[index]
          end

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
            all.concat(flatten_elements(element['elements'])) if element['elements']
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

      def user_columns(row, system_columns)
        system_column_names = system_columns.keys.map {|k| row[system_columns[k]]}

        row.clone.tap do |user_columns|
          system_columns.each do |column, index|
            user_columns.delete_if {|v| system_column_names.include?(v)}
          end
        end
      end

      def find_system_columns(headers)
        lat_columns = ['lat', 'latitude', 'y']
        lon_columns = ['lon', 'long', 'longitude', 'x']

        {
          latitude: headers.index          {|h| lat_columns.include?(h.downcase) },
          longitude: headers.index         {|h| lon_columns.include?(h.downcase) },
          project: headers.index           {|h| h == 'project' },
          status: headers.index            {|h| h == 'status' },
          client_created_at: headers.index {|h| h == 'created_at' },
          client_updated_at: headers.index {|h| h == 'updated_at' },
        }.delete_if {|k, v| v.nil?}
      end

      def find_photo_column(headers)
        photo_column = ['photo']

        {
          photo: headers.index             {|h| h == 'photo' }
        }.delete_if {|k, v| v.nil?}
      end

      def find_geo_columns(headers)
        lat_columns = ['lat', 'latitude', 'y']
        lon_columns = ['lon', 'long', 'longitude', 'x']
        [headers.index {|h| lat_columns.include?(h.downcase)}, headers.index {|h| lon_columns.include?(h.downcase)}]
      end
    end
  end
end

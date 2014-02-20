# tofulcrum

Import CSV data into an existing Fulcrum app from the command line.

## Installation

    $ gem install tofulcrum

## Usage

### Importing Data

    $ tofulcrum import somefile.csv <form_id> <api_key>

### Converting Excel files to Fulcrum format

    $ tofulcrum xls form_template.xls

## Notes

It will automatically map the column headers to the data names in the form. If any column is not found, it will fail. So your CSV
must only contain columns with valid fields in the form. Right now this program only supports text fields and choice fields.

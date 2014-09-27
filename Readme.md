### Brisket
#### A BBQ and Kitchen monitoring backend/frontend
***

![Brisket BBQ Monitor](http://static.grantsprunger.com/brisket.jpg)

### How to Use
#### Brisket uses Sinatra and mySQL
***

  ```bash
  # Install the required gems
  gem install
  
  # Setup the mySQL database env variables
  export BRISKET_DATABSE_USER=""
  export BRISKET_DATABSE_PASSWORD=""
  export BRISKET_DATABSE=""

  # Run the app
  ruby app.rb
  ```

### Send temperature updates
***

You can send temperatures via a post request to /publish with probe0 and probe1 parameters.

You can also use this Arduino sketch https://github.com/grantsprunger/brisket-arduino
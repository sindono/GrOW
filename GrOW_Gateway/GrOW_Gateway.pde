/*
Sketch:		GrOW Gateway
Version:	0.1
Status:         In progress
Date:           17 december 2010
Author:		@ArnoJansen for @sindono 
License:        To be determined, but for now its completely open.
Contact:	www.sindono.com

Description:
This project was inspired by an article in Make Magazine, called Garduino.
This program monitors and controls the environment in a greenhouse or vegetable garden. Besides keeping the environment optimal for growth, it reports about its measurements and actions wirelessly to a receiving, internet enabled gateway unit.

Note:
This gateway sketch receives measurements wirelessly via Xbee from a GrOW_Gateway. The gateway connects to the internet via ethernet. The hardware setup is an Arduino (duemilanove or newer) equipped with an ethernet shield and xbee shield, running the xbee in API mode.
*/
 
#include <XBee.h>
#include <SPI.h>
#include <Ethernet.h>

// Setting up Ethernet/Pachube 
// assign a MAC address for the ethernet controller.
// fill in your address here:
byte mac[] = { 
  0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED};
// assign an IP address for the controller:
byte ip[] = { 
  10,0,1,100 };
byte gateway[] = {
  10,0,1,1};	
byte subnet[] = { 
  255, 255, 255, 0 };

//  The address of the server you want to connect to (pachube.com):
byte server[] = { 
  209,40,205,190 }; 

// initialize the library instance:
Client client(server, 80);

long lastConnectionTime = 0;        // last time you connected to the server, in milliseconds
boolean lastConnected = false;      // state of the connection last time through the main loop
const int postingInterval = 10000;  //delay between updates to Pachube.com

/*
This example is for Series 2 XBee
Receives a ZB RX packet and sets a PWM value based on packet data.
Error led is flashed if an unexpected packet is received
*/

XBee xbee = XBee();
XBeeResponse response = XBeeResponse();
// create reusable response objects for responses we expect to handle 
ZBRxResponse rx = ZBRxResponse();
ModemStatusResponse msr = ModemStatusResponse();

int statusLed = 7;
int errorLed = 6;
int dataLed = 9;

void flashLed(int pin, int times, int wait) {
    
    for (int i = 0; i < times; i++) {
      digitalWrite(pin, HIGH);
      delay(wait);
      digitalWrite(pin, LOW);
      
      if (i + 1 < times) {
        delay(wait);
      }
    }
}

void setup() {
    // start the ethernet connection and serial port:
  Ethernet.begin(mac, ip);
  //String dataString = "";

  // give the ethernet module time to boot up:
  delay(1000);
  pinMode(statusLed, OUTPUT);
  pinMode(errorLed, OUTPUT);
  pinMode(dataLed,  OUTPUT);
  
  // start serial
  xbee.begin(9600);
  
  flashLed(statusLed, 3, 50);
}

// continuously reads packets, looking for ZB Receive or Modem Status
void loop() {
    
    xbee.readPacket();
    
    if (xbee.getResponse().isAvailable()) {
      // got something
      
      if (xbee.getResponse().getApiId() == ZB_RX_RESPONSE) {
        // got a zb rx packet
        
        // now fill our zb rx class
        xbee.getResponse().getZBRxResponse(rx);
            
        if (rx.getOption() == ZB_PACKET_ACKNOWLEDGED) {
            // the sender got an ACK
            flashLed(statusLed, 10, 10);
        } else {
            // we got it (obviously) but sender didn't get an ACK
            flashLed(errorLed, 2, 20);
        }
        // set dataLed PWM to value of the first byte in the data
        analogWrite(dataLed, rx.getData(0));
        // process the data from here on
        uint8_t* rxData = rx.getData();
        //int rxDataSize = strlen(rxData);
        Serial.println("Received data:");
        Serial.println("<START DATA>");
        String dataString = "";
        for (int i = 0; i < 35; i++) {
          
          // To save space, the decimal of the temp is omitted in transmission
          // reinsert here. First two digits are whole degrees, then a . followed by decimal temp.
          dataString +=  rx.getData(i);
          
          Serial.print(rx.getData(i), BYTE);
        }
        Serial.println("<END DATA>");
        // ITODO: Check for the data length vs checksum
        // Now do the Pachube thing from here

        int firstComma = dataString.indexOf(',');
        int hashSign = dataString.indexOf('#');
        String pachubeString = dataString.substring(firstComma+1, hashSign);
        Serial.print("PachubeString: [");
        Serial.print(pachubeString);
        Serial.println("]");
        
        //The Pachube string data is the part from the DataString after the device name until the hash
        // if there's incoming data from the net connection.
        // send it out the serial port.  This is for debugging
        // purposes only:
        if (client.available()) {
        char c = client.read();
        Serial.print(c);
        }
        
          // if there's no net connection, but there was one last time
        // through the loop, then stop the client:
        if (!client.connected() && lastConnected) {
          Serial.println();
          Serial.println("disconnecting.");
          client.stop();
        }
        
        // if you're not connected, and ten seconds have passed since
        // your last connection, then connect again and send data:
       if(!client.connected() && (millis() - lastConnectionTime > postingInterval)) {
          sendData(pachubeString);
          Serial.println("Sent data:");
          Serial.println(pachubeString);
          client.stop();
       }
       // store the state of the connection for next time through
       // the loop:
       lastConnected = client.connected();
        // to here

      } else if (xbee.getResponse().getApiId() == MODEM_STATUS_RESPONSE) {
        xbee.getResponse().getModemStatusResponse(msr);
        // the local XBee sends this response on certain events, like association/dissociation
        
        if (msr.getStatus() == ASSOCIATED) {
          // yay this is great.  flash led
          flashLed(statusLed, 10, 10);
        } else if (msr.getStatus() == DISASSOCIATED) {
          // this is awful.. flash led to show our discontent
          flashLed(errorLed, 10, 10);
        } else {
          // another status
          flashLed(statusLed, 5, 10);
        }
      } else {
      	// not something we were expecting
        flashLed(errorLed, 1, 25);    
      }
    }
}

// this method makes a HTTP connection to the server:
void sendData(String thisData) {
  // if there's a successful connection:
  if (client.connect()) {
    Serial.println("connecting...");
    // send the HTTP PUT request. 
    // fill in your feed address here:
    client.print("PUT /api/11261.csv HTTP/1.1\n");
    client.print("Host: www.pachube.com\n");
    // fill in your Pachube API key here:
    client.print("X-PachubeApiKey: <INSERT YOUR API KEY HERE>\n");
    client.print("Content-Length: ");
    client.println(thisData.length(), DEC);

    // last pieces of the HTTP PUT request:
    client.print("Content-Type: text/csv\n");
    client.println("Connection: close\n");

    // here's the actual content of the PUT request:
    client.println(thisData);

    // note the time that the connection was made:
    lastConnectionTime = millis();
  } 
  else {
    // if you couldn't make a connection:
    Serial.println("connection failed");
  }
}


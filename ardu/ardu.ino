#define SHOCK_PIN 2
#define INTENSITY_UP_PIN 3
#define INTENSITY_DOWN_PIN 4


int old_intensity = 1;

void setup() {
  // Initialize serial communication:
  Serial.begin(9600);
  // Set pins as output
  
  pinMode(SHOCK_PIN, OUTPUT);
  pinMode(INTENSITY_UP_PIN, OUTPUT);
  pinMode(INTENSITY_DOWN_PIN, OUTPUT);
  digitalWrite(SHOCK_PIN, HIGH);
  digitalWrite(INTENSITY_UP_PIN, HIGH);
  digitalWrite(INTENSITY_DOWN_PIN, HIGH);
}

void shock(int wait) {
  // Set pin high
  digitalWrite(SHOCK_PIN, LOW);
  // Wait for intensity milliseconds
  delay(wait);
  // Set pin low
  digitalWrite(SHOCK_PIN, HIGH);
  Serial.println("Shock finished.");
}

void intensity(int intensity) {
  // Set pin high
  int delta = intensity - old_intensity;
  if (delta==0){
    return;
  }
  else if (delta > 0){
    for(int i = 0; i<delta; i++){
      digitalWrite(INTENSITY_UP_PIN, LOW);
      delay(50); // You can modify this if needed
      // Set pin low
      digitalWrite(INTENSITY_UP_PIN, HIGH);
    }
  }
  else{
    for(int i = 0; i<delta*-1; i++){
      digitalWrite(INTENSITY_DOWN_PIN, LOW);
      delay(50); // You can modify this if needed
      // Set pin low
      digitalWrite(INTENSITY_DOWN_PIN, HIGH);
    }
  }
  
  Serial.println("Intensity finished.");
}

void loop() {
  // Wait for the first byte of data to arrive
  while (Serial.available() < 2) {
    // Do nothing
  }

  // Read the two bytes and combine them into a 16-bit integer
  int16_t receivedValue = Serial.read() | (Serial.read() << 8);

  // Extract the first bit (bit 15)
  bool isFirstBitSet = (receivedValue >> 15) & 0x01;

  // Extract the last 15 bits
  int value = receivedValue & 0x7FFF;

  // Call the appropriate function based on the first bit
  if (isFirstBitSet) {
    shock(value); // Call the "shock" function
  } else {
    intensity(value); // Call the "intensity" function
  }

  // Optional: delay before reading the next value
  delay(1000);
}

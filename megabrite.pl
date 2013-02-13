#!/usr/bin/perl

use Time::HiRes qw( sleep );
use strict;

use Device::BCM2835;
Device::BCM2835::init() || die "Could not init library";

# Designate GPIO pins
# 	(See list of constants: http://www.open.com.au/mikem/bcm2835/group__constants.html#ga63c029bd6500167152db4e57736d0939)
my $serial = &Device::BCM2835::RPI_GPIO_P1_21;
my $clock = &Device::BCM2835::RPI_GPIO_P1_23;
my $latch = &Device::BCM2835::RPI_GPIO_P1_24;
my $outputenable = &Device::BCM2835::RPI_GPIO_P1_26;

# Put them in "Output" mode
Device::BCM2835::gpio_fsel($serial, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
Device::BCM2835::gpio_fsel($clock, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
Device::BCM2835::gpio_fsel($latch, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
Device::BCM2835::gpio_fsel($outputenable, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);

# Quick GPIO howto:
# 	Set pin high (+3.3V):
#		Device::BCM2835::gpio_set($pin)
#
#	Set pin low (GND): 
#		Device::BCM2835::gpio_clr($pin)

# $outputenable is the global on/off switch, but the logic is
# inverted: set it low to turn everything on.
Device::BCM2835::gpio_clr($outputenable);
Device::BCM2835::delayMicroseconds(1);

# Give the red LED more juice to compensate for human hardware quirks
&setBrite(control => 1, red => 127, green => 31, blue => 31);

# Build a table of map values to relate actual brightness to perceived
# brightness (see http://jared.geek.nz/blog/2013/feb/linear-led-pwm)
my @cie;
for my $y (0 .. 1023) {
	my $z = $y / 1023;
	if ( ($z * 100) <= 8) { $cie[$y] = int( ($z * 100 / 902.3) * 1023); }
	else                  { $cie[$y] = int( ((($z * 100) + 16) / 116)**3 * 1024); }
}

# Seconds between each change in brightness
my $fade_delay = 0.01;

my %pwm = (red => 0, green => 0, blue => 0);

for (1 .. 2) {
	for my $fadecolor ("red", "green", "blue") {
		# Ramp up quickly...
		while ($pwm{$fadecolor} < 1024) {
			$pwm{$fadecolor} += 64;
			&setBrite(red => $pwm{red}, green => $pwm{green}, blue => $pwm{blue});
			sleep($fade_delay);
		}

		# ...then fade down slowly
		while ($pwm{$fadecolor} > 0) {
			$pwm{$fadecolor} -= 16;
			&setBrite(red => $pwm{red}, green => $pwm{green}, blue => $pwm{blue});
			sleep($fade_delay);
		}
	}
}

exit 0;


sub setBrite {
	my %color = @_;

	# This is the serial word we'll send to the MegaBrite
	my $sendword = 0;

	# Equivalent, but more illustrative of the 32 bits we intend to send:
	#my $sendword = 0b00000000000000000000000000000000;

	if (exists $color{control}) {
		# Current control mode: cut off anything longer than 7 bits, and set control mode
		$color{red} %= 128;
		$color{green} %= 128;
		$color{blue} %= 128;
		$sendword = (1<<30);
	}
	else {
		# Brightness mode

		# Min/max the received value to appropriate limits
		for my $z ("red", "green", "blue") {
			$color{$z} = 0 if ($color{$z} < 0);
			$color{$z} = 1023 if ($color{$z} > 1023);
		}

		# Adjust desired brightness based on human perception bias
		$color{red} = $cie[$color{red}];
		$color{green} = $cie[$color{green}];
		$color{blue} = $cie[$color{blue}];
	}

	# Construct the word by shifting each value to the appropriate offset and
	# logically OR-ing them. If this is a control word, a "1" was set earlier
	# at the appropriate position.
	$sendword |= ($color{blue} << 20) | ($color{red} << 10) | ($color{green});

	for (my $x = 31; $x > -1; $x--) {
		if ($sendword & (1<<$x)) { &sendBit(1); }
		else                     { &sendBit(0); }
	}
	&latch;
}

sub sendBit {
	# Prepare the $serial pin with the appropriate value
	my $bit = shift @_;
	if ($bit) {
		Device::BCM2835::gpio_set($serial);
	}
	else {
		Device::BCM2835::gpio_clr($serial);
	}
	&clockOut;
}

sub clockOut {
	# Momentarily draw the device's attention to the current value on $serial
	Device::BCM2835::gpio_set($clock);
	Device::BCM2835::delayMicroseconds(1);
	Device::BCM2835::gpio_clr($clock);
	Device::BCM2835::delayMicroseconds(1);
}

sub latch {
	# Instruct the device to implement the most recent word
	Device::BCM2835::gpio_set($latch);
	Device::BCM2835::delayMicroseconds(15);
	Device::BCM2835::gpio_clr($latch);
	Device::BCM2835::delayMicroseconds(15);
}


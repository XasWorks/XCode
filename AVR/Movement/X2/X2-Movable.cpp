/*
 * X2-Movable.cpp
 *
 *  Created on: Oct 5, 2016
 *      Author: xasin
 */

#include "X2-Movable.h"

// If in is below max, return in
// Otherwise however, return max with the sign of in, so that no value greater than max is returned
float clamp(float in, float max) {
	return (fabs(in) > fabs(max)) ?
		copysign(max, in) :
		in;
}

namespace X2 {

// Empty constructor
Movable::Movable(uint16_t updateFrequency) : updateFrequency(updateFrequency) {
}

// Set the rotation speed
void Movable::setRotationSpeed(float speed) {
	this->rSpeed = clamp(speed, SANE_RSPEED_MAX)/(float)updateFrequency;
}
// Set the movement speed
void Movable::setSpeed(float speed) {
	this->mSpeed = clamp(speed, SANE_MSPEED_MAX)/(float)updateFrequency;
}
void Movable::setSpeeds(float mSpeed, float rSpeed) {
	this->setRotationSpeed(rSpeed);
	this->setSpeed(mSpeed);
}

void Movable::rotateBy(float angle) {
	this->mode = relative;
	this->rAngle = angle;
}
void Movable::rotateF(float angle) {
	this->rotateBy(angle);
	this->flush();
}

void Movable::moveBy(float distance) {
	this->mode = relative;
	this->mDistance = distance;
}
void Movable::moveF(float distance) {
	this->moveBy(distance);
	this->flush();
}

void Movable::continuousMode() {
	this->mode = continuous;
	this->mDistance = 0;
	this->rAngle = 0;
}
void Movable::continuousMode(float mSpeed, float rSpeed) {
	this->setSpeeds(mSpeed, rSpeed);
	this->continuousMode();
}

bool Movable::atPosition() {
	return fabs(this->mDistance) < 0.1;
}
bool Movable::atRotation() {
	return fabs(this->rAngle) < 0.1;
}
bool Movable::isReady() {
	return (this->atPosition() && this->atRotation());
}

void Movable::flush() {
	while(!this->isReady()) {
		_delay_ms(1);
	}
}
void Movable::cancel() {
	this->mDistance = 0;
	this->rAngle = 0;
	this->mode = relative;
}

void Movable::update() {
	float xThisCal;
	float rThisCal;

	switch(mode) {

		case relative:
		xThisCal = clamp(mDistance, fabs(mSpeed));
		rThisCal = clamp(rAngle, fabs(rSpeed));

		mDistance -= xThisCal;
		rAngle -= rThisCal;

		Actuator::ISRStepAllBy(xThisCal, rThisCal);
		movedDistance += xThisCal;
		movedRotation += rThisCal;
		break;

		case continuous:
		Actuator::ISRStepAllBy(mSpeed, rSpeed);
		movedDistance += mSpeed;
		movedRotation += rSpeed;
		break;
	}
}

}

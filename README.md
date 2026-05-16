# AWS-project-1
ALB path based routing project

**Project 1**
AWS ALB Path-Based Routing Setup
Configuration Overview
- ALB Listener Rules are configured to route traffic based on request paths:
- / → Target Group A (Homepage)
- /images → Target Group B (Images)
- /register → Target Group C (Registration)
- Each Target Group contains EC2 instances in separate Availability Zones (AZs) to ensure high availability.
EC2 Instance Roles
- Instance A: Serves homepage (/)
- Instance B: Serves /images
- Instance C: Serves /register
EC2 Initialization
Each EC2 instance uses a user_data script to:
- Install and start the Nginx service
- Configure Nginx to serve content for its designated path
Routing Behavior (Verified via Browser)
- Accessing http://my-alb-1825664422.eu-:
- Instance A responds with "Images!"
- Instance B responds with "Images!"
- Instance C responds with "Register!"
This confirms that:
- The ALB correctly routes traffic based on path rules.
- EC2 instances are serving the expected content.
- Listener rules are functioning as intended.
Expected Outcomes
- Requests to / go to the homepage instance in AZ1.
- Requests to /images go to the image-serving instance in AZ2.
- Requests to /register go to the registration instance in AZ3.
---

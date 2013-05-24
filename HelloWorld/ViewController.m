//
//  ViewController.m
//  HelloWorld
//
//  Created by Varun Murali on 5/23/13.
//  Copyright (c) 2013 Originate. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    self.view = [[UIView alloc] init];
    self.view.backgroundColor = [UIColor whiteColor];
    hello = [[UILabel alloc] initWithFrame:CGRectMake(01, 10, 150, 50)];
    hello.text = @"Hello World! This is an update!";
    [self.view addSubview:hello];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

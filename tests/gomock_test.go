package main

import (
	"testing"

	"github.com/golang/mock/gomock"
)

func TestGoldenPath(t *testing.T) {
	ctrl := gomock.NewController(t)
	m := NewMockHelloer(ctrl)
	m.EXPECT().Hello().Return("hey")
	m.Hello()
	defer ctrl.Finish()
}

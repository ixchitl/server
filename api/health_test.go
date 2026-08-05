package api

import (
	"encoding/json"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/gotify/server/v2/mode"
	"github.com/gotify/server/v2/model"
	"github.com/gotify/server/v2/test/testdb"
	"github.com/stretchr/testify/suite"
)

func TestHealthSuite(t *testing.T) {
	suite.Run(t, new(HealthSuite))
}

type HealthSuite struct {
	suite.Suite
	db       *testdb.Database
	a        *HealthAPI
	ctx      *gin.Context
	recorder *httptest.ResponseRecorder
}

func (s *HealthSuite) BeforeTest(suiteName, testName string) {
	mode.Set(mode.TestDev)
	s.recorder = httptest.NewRecorder()
	s.db = testdb.NewDB(s.T())
	s.ctx, _ = gin.CreateTestContext(s.recorder)
	withURL(s.ctx, "http", "example.com")
	s.a = NewHealthAPI(s.db, "test-version")
}

func (s *HealthSuite) AfterTest(suiteName, testName string) {
	s.db.Close()
}

func (s *HealthSuite) TestHealthSuccess() {
	s.a.Health(s.ctx)

	var health model.Health
	s.Require().NoError(json.Unmarshal(s.recorder.Body.Bytes(), &health))
	s.Require().Equal(200, s.recorder.Code)
	s.Require().Equal(model.StatusGreen, health.Health)
	s.Require().Equal(model.StatusGreen, health.Database)
	s.Require().Equal("test-version", health.Version)
	s.Require().GreaterOrEqual(health.Uptime, int64(0))
}

func (s *HealthSuite) TestDatabaseFailure() {
	s.db.Close()
	s.a.Health(s.ctx)

	var health model.Health
	s.Require().NoError(json.Unmarshal(s.recorder.Body.Bytes(), &health))
	s.Require().Equal(500, s.recorder.Code)
	s.Require().Equal(model.StatusOrange, health.Health)
	s.Require().Equal(model.StatusRed, health.Database)
	s.Require().Equal("test-version", health.Version)
	s.Require().GreaterOrEqual(health.Uptime, int64(0))
}

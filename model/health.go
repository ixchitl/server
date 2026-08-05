package model

// Health Model
//
// Health represents how healthy the application is.
//
// swagger:model Health
type Health struct {
	// The health of the overall application.
	//
	// required: true
	// example: green
	Health string `json:"health"`
	// The health of the database connection.
	//
	// required: true
	// example: green
	Database string `json:"database"`
	// The time the server has been running.
	//
	// required: true
	// example: 50080
	Uptime int64 `json:"uptime"`
	// The version of the server.
	//
	// required: true
	// example: 2.2.0
	Version string `json:"version"`
}

const (
	// StatusGreen everything is alright.
	StatusGreen = "green"
	// StatusOrange some things are alright.
	StatusOrange = "orange"
	// StatusRed nothing is alright.
	StatusRed = "red"
)

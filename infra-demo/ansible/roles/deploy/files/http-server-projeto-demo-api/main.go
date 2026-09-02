package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	serviceUp = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "http_server_up",
		Help: "Indica se o serviço http-server-projeto-demo-api está ativo (1 = up, 0 = down)",
	})

	httpRequestsTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total de requisições HTTP recebidas",
	}, []string{"method", "endpoint", "status_code"})
)

func init() {
	prometheus.MustRegister(serviceUp)
	prometheus.MustRegister(httpRequestsTotal)
	serviceUp.Set(1)
}

type Response struct {
	App     string `json:"app"`
	Horario string `json:"horario"`
}

func apiInfoHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		httpRequestsTotal.WithLabelValues(r.Method, "/api-info", "405").Inc()
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	response := Response{
		App:     "SRE Demo API",
		Horario: time.Now().UTC().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
	httpRequestsTotal.WithLabelValues(r.Method, "/api-info", "200").Inc()
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func main() {
	http.HandleFunc("/api-info", apiInfoHandler)
	http.HandleFunc("/health", healthHandler)
	http.Handle("/metrics", promhttp.Handler())

	log.Println("http-server-projeto-demo-api listening on :8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		serviceUp.Set(0)
		log.Fatalf("Server failed to start: %v", err)
	}
}

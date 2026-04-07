import "@hotwired/turbo-rails";
import "controllers";

// Flash message functionality
document.addEventListener('DOMContentLoaded', function() {
  // Clear any existing flash messages after a short delay to prevent persistence
  setTimeout(function() {
    const alerts = document.querySelectorAll('.alert');
    if (alerts.length > 0) {
      alerts.forEach(function(alert) {
        if (alert && alert.parentNode) {
          alert.style.transition = 'opacity 0.5s ease-out, transform 0.5s ease-out';
          alert.style.opacity = '0';
          alert.style.transform = 'translateY(-100%) translateX(-50%)';
          setTimeout(function() {
            if (alert && alert.parentNode) {
              alert.parentNode.removeChild(alert);
            }
          }, 500);
        }
      });
    }
  }, 100);

  // Auto-hide flash messages after 10 seconds (increased from 5)
  const alerts = document.querySelectorAll('.alert');
  alerts.forEach(function(alert) {
    setTimeout(function() {
      if (alert && alert.parentNode) {
        alert.style.transition = 'opacity 0.5s ease-out, transform 0.5s ease-out';
        alert.style.opacity = '0';
        alert.style.transform = 'translateY(-100%) translateX(-50%)';
        setTimeout(function() {
          if (alert && alert.parentNode) {
            alert.parentNode.removeChild(alert);
          }
        }, 500);
      }
    }, 10000); // Changed from 5000 to 10000 (10 seconds)
  });

  // Handle close button clicks
  document.addEventListener('click', function(e) {
    if (e.target.classList.contains('btn-close') || e.target.closest('.btn-close')) {
      const alert = e.target.closest('.alert');
      if (alert) {
        alert.style.transition = 'opacity 0.3s ease-out, transform 0.3s ease-out';
        alert.style.opacity = '0';
        alert.style.transform = 'translateY(-100%) translateX(-50%)';
        setTimeout(function() {
          if (alert && alert.parentNode) {
            alert.parentNode.removeChild(alert);
          }
        }, 300);
      }
    }
  });
});

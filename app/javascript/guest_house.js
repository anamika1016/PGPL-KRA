const initGuestHouse = () => {
  document.querySelectorAll("[data-guest-house-print]").forEach((button) => {
    if (button.dataset.guestHouseBound === "true") return;
    button.dataset.guestHouseBound = "true";
    button.addEventListener("click", () => window.print());
  });

  const checkinDate = document.getElementById("guest_house_booking_booking_date");
  const checkoutDate = document.getElementById("guest_house_booking_checkout_date");
  const checkinTime = document.getElementById("guest_house_booking_checkin_time");
  const checkoutTime = document.getElementById("guest_house_booking_checkout_time");

  if (checkinDate && checkoutDate && checkinDate.dataset.guestHouseBound !== "true") {
    checkinDate.dataset.guestHouseBound = "true";
    const syncCheckoutDate = () => {
      checkoutDate.min = checkinDate.value || checkoutDate.min;

      if (!checkoutDate.value || checkoutDate.value < checkinDate.value) {
        checkoutDate.value = checkinDate.value;
      }
    };

    checkinDate.addEventListener("change", syncCheckoutDate);
    syncCheckoutDate();
  }

  document.querySelectorAll("[data-guest-house-occupants]").forEach((section) => {
    const form = section.closest("form");
    const bookingFor = form?.querySelector("[data-guest-house-booking-for]");
    const guestCount = form?.querySelector("[data-guest-house-guest-count]");
    const parentScheduleFields = form?.querySelectorAll("[data-guest-house-parent-schedule-field]");
    const roomTypeField = form?.querySelector("[data-guest-house-room-type-field]");
    const countField = form?.querySelector("[data-guest-house-count-field]");
    const selfRoomType = form?.querySelector("[data-guest-house-self-room-type]");
    const selfRoomTypeInput = form?.querySelector("[data-guest-house-self-room-type-input]");
    const externalRoomType = form?.querySelector("[data-guest-house-external-room-type]");
    const externalRoomTypeInput = form?.querySelector("[data-guest-house-external-room-type-input]");
    const bookingGenderField = form?.querySelector("[data-guest-house-booking-gender-field]");
    const bookingGender = form?.querySelector("[data-guest-house-booking-gender]");
    const occupantTitle = section.querySelector("[data-guest-house-occupant-title]");
    const occupantCopy = section.querySelector("[data-guest-house-occupant-copy]");
    const list = section.querySelector("[data-guest-house-occupant-list]");
    const initialRow = list?.querySelector("[data-guest-house-occupant-row]");
    const singleRoomDesignation = /\b(md|m\.d\.|director|ceo|chief executive officer|managing director)\b/i;
    let previousBookingWindow = {
      checkinDate: checkinDate?.value || "",
      checkinTime: checkinTime?.value || "",
      checkoutDate: checkoutDate?.value || "",
      checkoutTime: checkoutTime?.value || ""
    };

    if (!form || !bookingFor || !guestCount || !list || !initialRow) return;
    if (section.dataset.guestHouseBound === "true") return;
    section.dataset.guestHouseBound = "true";

    const buildRow = (index) => {
      const row = initialRow.cloneNode(true);

      row.querySelectorAll("input, select, textarea").forEach((input) => {
        input.name = input.name.replace(/\[\d+\]/, `[${index}]`);
        input.id = input.id.replace(/_\d+_/, `_${index}_`);
        if (input.type === "checkbox") {
          input.checked = false;
        } else {
          input.value = "";
        }
      });

      row.querySelectorAll("label").forEach((label) => {
        if (label.htmlFor) label.htmlFor = label.htmlFor.replace(/_\d+_/, `_${index}_`);
      });

      return row;
    };

    const reindexRows = () => {
      Array.from(list.children).forEach((row, index) => {
        row.querySelectorAll("input, select, textarea").forEach((input) => {
          input.name = input.name.replace(/\[\d+\]/, `[${index}]`);
          input.id = input.id.replace(/_\d+_/, `_${index}_`);
        });

        row.querySelectorAll("label").forEach((label) => {
          if (label.htmlFor) label.htmlFor = label.htmlFor.replace(/_\d+_/, `_${index}_`);
        });
      });
    };

    const scheduleValue = (date, time) => {
      if (!date || !time) return "";

      return `${date}T${time}`;
    };

    const syncParentScheduleFromOccupants = () => {
      const activeRows = Array.from(list.querySelectorAll("[data-guest-house-occupant-row]:not([hidden])"));
      const schedules = activeRows.map((row) => {
        const occupantCheckinDate = row.querySelector("[data-guest-house-occupant-checkin-date]")?.value || "";
        const occupantCheckinTime = row.querySelector("[data-guest-house-occupant-checkin-time]")?.value || "";
        const occupantCheckoutDate = row.querySelector("[data-guest-house-occupant-checkout-date]")?.value || "";
        const occupantCheckoutTime = row.querySelector("[data-guest-house-occupant-checkout-time]")?.value || "";

        return {
          checkinDate: occupantCheckinDate,
          checkinTime: occupantCheckinTime,
          checkoutDate: occupantCheckoutDate,
          checkoutTime: occupantCheckoutTime,
          checkinValue: scheduleValue(occupantCheckinDate, occupantCheckinTime),
          checkoutValue: scheduleValue(occupantCheckoutDate, occupantCheckoutTime)
        };
      });

      const starts = schedules.filter((schedule) => schedule.checkinValue).sort((a, b) => a.checkinValue.localeCompare(b.checkinValue));
      const ends = schedules.filter((schedule) => schedule.checkoutValue).sort((a, b) => b.checkoutValue.localeCompare(a.checkoutValue));
      const firstStart = starts[0];
      const lastEnd = ends[0];

      if (firstStart) {
        if (checkinDate) checkinDate.value = firstStart.checkinDate;
        if (checkinTime) checkinTime.value = firstStart.checkinTime;
      }

      if (lastEnd) {
        if (checkoutDate) checkoutDate.value = lastEnd.checkoutDate;
        if (checkoutTime) checkoutTime.value = lastEnd.checkoutTime;
      }
    };

    const removeOccupantRow = (row) => {
      const activeRows = Array.from(list.querySelectorAll("[data-guest-house-occupant-row]:not([hidden])"));
      if (activeRows.length <= 1) return;

      row.remove();
      guestCount.value = Math.max(activeRows.length - 1, 1);
      reindexRows();
      syncRows();
    };

    const syncOccupantSchedule = (row, { fromParent = true } = {}) => {
      const occupantCheckinDate = row.querySelector("[data-guest-house-occupant-checkin-date]");
      const occupantCheckinTime = row.querySelector("[data-guest-house-occupant-checkin-time]");
      const occupantCheckoutDate = row.querySelector("[data-guest-house-occupant-checkout-date]");
      const occupantCheckoutTime = row.querySelector("[data-guest-house-occupant-checkout-time]");
      const bookingWindow = {
        checkinDate: checkinDate?.value || "",
        checkinTime: checkinTime?.value || "",
        checkoutDate: checkoutDate?.value || "",
        checkoutTime: checkoutTime?.value || ""
      };

      const syncValue = (input, currentValue, previousValue) => {
        if (input && (!input.value || input.value === previousValue)) input.value = currentValue;
      };

      if (fromParent) {
        syncValue(occupantCheckinDate, bookingWindow.checkinDate, previousBookingWindow.checkinDate);
        syncValue(occupantCheckinTime, bookingWindow.checkinTime, previousBookingWindow.checkinTime);
        syncValue(occupantCheckoutDate, bookingWindow.checkoutDate, previousBookingWindow.checkoutDate);
        syncValue(occupantCheckoutTime, bookingWindow.checkoutTime, previousBookingWindow.checkoutTime);
      }

      if (occupantCheckinDate) {
        occupantCheckinDate.min = fromParent && bookingWindow.checkinDate ? bookingWindow.checkinDate : occupantCheckinDate.min;
        if (fromParent && bookingWindow.checkinDate && occupantCheckinDate.value < bookingWindow.checkinDate) {
          occupantCheckinDate.value = bookingWindow.checkinDate;
        }
      }

      if (occupantCheckoutDate) {
        occupantCheckoutDate.min = occupantCheckinDate?.value || (fromParent ? bookingWindow.checkinDate : "") || occupantCheckoutDate.min;
        if (occupantCheckinDate?.value && occupantCheckoutDate.value < occupantCheckinDate.value) {
          occupantCheckoutDate.value = occupantCheckinDate.value;
        }
        if (fromParent && bookingWindow.checkoutDate && occupantCheckoutDate.value > bookingWindow.checkoutDate) {
          occupantCheckoutDate.value = bookingWindow.checkoutDate;
        }
      }

      if (
        occupantCheckinDate?.value &&
        occupantCheckinTime &&
        fromParent &&
        bookingWindow.checkinDate &&
        bookingWindow.checkinTime &&
        occupantCheckinDate.value === bookingWindow.checkinDate &&
        occupantCheckinTime.value < bookingWindow.checkinTime
      ) {
        occupantCheckinTime.value = bookingWindow.checkinTime;
      }

      if (
        occupantCheckoutDate?.value &&
        occupantCheckoutTime &&
        fromParent &&
        bookingWindow.checkoutDate &&
        bookingWindow.checkoutTime &&
        occupantCheckoutDate.value === bookingWindow.checkoutDate &&
        occupantCheckoutTime.value > bookingWindow.checkoutTime
      ) {
        occupantCheckoutTime.value = bookingWindow.checkoutTime;
      }

      if (
        occupantCheckinDate?.value &&
        occupantCheckoutDate?.value &&
        occupantCheckinTime?.value &&
        occupantCheckoutTime?.value &&
        fromParent &&
        occupantCheckinDate.value === occupantCheckoutDate.value &&
        occupantCheckoutTime.value <= occupantCheckinTime.value
      ) {
        const parentCheckoutIsValid =
          bookingWindow.checkoutDate === occupantCheckoutDate.value &&
          bookingWindow.checkoutTime &&
          bookingWindow.checkoutTime > occupantCheckinTime.value;
        if (parentCheckoutIsValid) occupantCheckoutTime.value = bookingWindow.checkoutTime;
      }
    };

    const syncRows = () => {
      const count = Math.max(Number.parseInt(guestCount.value || "1", 10) || 1, 1);
      const selfBooking = bookingFor.value === "self";
      const externalBooking = bookingFor.value === "guest" || bookingFor.value === "auditor";
      const bookingSelected = selfBooking || externalBooking;
      const label = bookingFor.value === "auditor" ? "Auditor" : "Guest";

      section.hidden = !externalBooking;
      if (roomTypeField) roomTypeField.hidden = !bookingSelected;
      if (countField) {
        countField.hidden = !bookingSelected;
        countField.querySelectorAll("input, select, textarea").forEach((input) => {
          input.disabled = !bookingSelected;
          input.required = bookingSelected;
        });
      }
      parentScheduleFields?.forEach((field) => {
        field.hidden = !selfBooking;
        field.querySelectorAll("input, select, textarea").forEach((input) => {
          input.disabled = !selfBooking && !externalBooking;
          input.required = selfBooking;
        });
      });
      if (bookingGenderField) {
        bookingGenderField.hidden = !selfBooking;
        bookingGenderField.querySelectorAll("input, select, textarea").forEach((input) => {
          input.disabled = !selfBooking;
          input.required = selfBooking;
        });
      }
      if (occupantTitle) occupantTitle.textContent = `${label} Details`;
      if (occupantCopy) occupantCopy.textContent = `Enter details for each ${label.toLowerCase()} included in this booking.`;
      if (selfRoomType) selfRoomType.hidden = !selfBooking;
      if (selfRoomTypeInput) selfRoomTypeInput.disabled = !selfBooking;
      if (externalRoomType) externalRoomType.hidden = !externalBooking;
      if (externalRoomTypeInput) {
        externalRoomTypeInput.disabled = !externalBooking;
        externalRoomTypeInput.required = externalBooking;
      }

      while (list.children.length < count) {
        list.appendChild(buildRow(list.children.length));
      }

      reindexRows();

      Array.from(list.children).forEach((row, index) => {
        const rowActive = externalBooking && index < count;
        row.hidden = !rowActive;
        const occupantNumber = row.querySelector("[data-guest-house-occupant-number]");
        const removeButton = row.querySelector("[data-guest-house-remove-occupant]");

        if (occupantNumber) occupantNumber.textContent = `${label} ${index + 1}`;
        if (removeButton) removeButton.hidden = !rowActive || count <= 1;

        row.querySelectorAll("input, select, textarea").forEach((input) => {
          input.disabled = !rowActive;
          input.required = rowActive && input.hasAttribute("data-guest-house-occupant-required");
        });

        if (rowActive) {
          syncOccupantSchedule(row, { fromParent: !externalBooking });
        }
      });

      if (externalBooking) syncParentScheduleFromOccupants();

      if (externalBooking && externalRoomTypeInput) {
        const activeDesignations = Array.from(list.querySelectorAll("[data-guest-house-occupant-row]:not([hidden]) [data-guest-house-occupant-designation]"));
        const singleRoomEligible = activeDesignations.length === count &&
          activeDesignations.every((input) => singleRoomDesignation.test(input.value.trim()));
        const existingSingleOption = externalRoomTypeInput.querySelector('option[value="single"]');

        if (singleRoomEligible && !existingSingleOption) {
          externalRoomTypeInput.add(new Option("Single Room", "single"));
        } else if (!singleRoomEligible && existingSingleOption) {
          existingSingleOption.remove();
        }

        externalRoomTypeInput.value = singleRoomEligible ? "single" : "sharing";
      }

      if (externalBooking && bookingGender) {
        const firstGender = list.querySelector("[data-guest-house-occupant-row]:not([hidden]) [data-guest-house-occupant-gender]")?.value;
        if (firstGender) bookingGender.value = firstGender;
      }

      previousBookingWindow = {
        checkinDate: checkinDate?.value || "",
        checkinTime: checkinTime?.value || "",
        checkoutDate: checkoutDate?.value || "",
        checkoutTime: checkoutTime?.value || ""
      };
    };

    bookingFor.addEventListener("change", syncRows);
    guestCount.addEventListener("input", syncRows);
    guestCount.addEventListener("change", syncRows);
    [ checkinDate, checkinTime, checkoutDate, checkoutTime ].forEach((input) => input?.addEventListener("change", syncRows));
    form.addEventListener("submit", () => {
      if (bookingFor.value === "guest" || bookingFor.value === "auditor") syncParentScheduleFromOccupants();
    });
    list.addEventListener("change", (event) => {
      if (
        event.target.matches("[data-guest-house-occupant-gender]") ||
        event.target.matches("[data-guest-house-occupant-checkin-date]") ||
        event.target.matches("[data-guest-house-occupant-checkin-time]") ||
        event.target.matches("[data-guest-house-occupant-checkout-date]") ||
        event.target.matches("[data-guest-house-occupant-checkout-time]")
      ) syncRows();
    });
    list.addEventListener("click", (event) => {
      const removeButton = event.target.closest("[data-guest-house-remove-occupant]");
      if (!removeButton) return;

      removeOccupantRow(removeButton.closest("[data-guest-house-occupant-row]"));
    });
    list.addEventListener("input", (event) => {
      if (event.target.matches("[data-guest-house-occupant-designation]")) syncRows();
    });
    syncRows();
  });

  document.querySelectorAll("[data-guest-house-billing]").forEach((form) => {
    if (form.dataset.guestHouseBound === "true") return;
    form.dataset.guestHouseBound = "true";
    const money = new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      minimumFractionDigits: 2
    });

    const roomAmount = form.querySelector("[data-guest-house-room-amount]");
    const roomOverride = form.querySelector("[data-guest-house-room-override]");
    const manualAmount = form.querySelector("[data-guest-house-manual-amount]");
    const facilityTotal = form.querySelector("[data-guest-house-facility-total]");
    const gstTotal = form.querySelector("[data-guest-house-gst-total]");
    const grandTotal = form.querySelector("[data-guest-house-grand-total]");
    const roomTotal = form.querySelector("[data-guest-house-room-total]");

    const calculate = () => {
      let selectedFacilityTotal = 0;

      form.querySelectorAll("[data-guest-house-facility-check]").forEach((checkbox) => {
        const option = checkbox.closest(".guest-house-facility-option");
        const quantityInput = option?.querySelector("[data-guest-house-facility-qty]");
        const quantity = Math.max(Number.parseInt(quantityInput?.value || "1", 10) || 1, 1);
        const rate = Number.parseFloat(checkbox.dataset.rate || "0") || 0;

        if (quantityInput) {
          quantityInput.disabled = !checkbox.checked;
        }

        if (checkbox.checked) {
          selectedFacilityTotal += rate * quantity;
        }
      });

      const roomCharge = Math.max(Number.parseFloat(roomAmount?.value || "0") || 0, 0);
      const manual = Math.max(Number.parseFloat(manualAmount?.value || "0") || 0, 0);
      const taxable = roomCharge + selectedFacilityTotal + manual;
      const gst = taxable * 0.05;
      const total = taxable + gst;

      if (roomTotal) roomTotal.textContent = money.format(roomCharge);
      if (facilityTotal) facilityTotal.textContent = money.format(selectedFacilityTotal + manual);
      if (gstTotal) gstTotal.textContent = money.format(gst);
      if (grandTotal) grandTotal.textContent = money.format(total);
    };

    const syncRoomOverride = () => {
      if (roomAmount && roomOverride) roomAmount.disabled = !roomOverride.checked;
    };

    form.addEventListener("input", calculate);
    form.addEventListener("change", () => {
      syncRoomOverride();
      calculate();
    });
    syncRoomOverride();
    calculate();
  });
};

document.addEventListener("turbo:load", initGuestHouse);
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initGuestHouse, { once: true });
} else {
  initGuestHouse();
}

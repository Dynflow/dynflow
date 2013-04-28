require_dependency "dynflow/application_controller"

module Dynflow
  class JournalsController < ApplicationController
    # GET /journals
    # GET /journals.json
    def index
      @journals = Journal.all
  
      respond_to do |format|
        format.html # index.html.erb
        format.json { render json: @journals }
      end
    end
  
    # GET /journals/1
    # GET /journals/1.json
    def show
      @journal = Journal.find(params[:id])
  
      respond_to do |format|
        format.html # show.html.erb
        format.json { render json: @journal }
      end
    end
  
    # GET /journals/new
    # GET /journals/new.json
    def new
      @journal = Journal.new
  
      respond_to do |format|
        format.html # new.html.erb
        format.json { render json: @journal }
      end
    end
  
    # GET /journals/1/edit
    def edit
      @journal = Journal.find(params[:id])
    end
  
    # POST /journals
    # POST /journals.json
    def create
      @journal = Journal.new(params[:journal])
  
      respond_to do |format|
        if @journal.save
          format.html { redirect_to @journal, notice: 'Journal was successfully created.' }
          format.json { render json: @journal, status: :created, location: @journal }
        else
          format.html { render action: "new" }
          format.json { render json: @journal.errors, status: :unprocessable_entity }
        end
      end
    end
  
    # PUT /journals/1
    # PUT /journals/1.json
    def update
      @journal = Journal.find(params[:id])
  
      respond_to do |format|
        if @journal.update_attributes(params[:journal])
          format.html { redirect_to @journal, notice: 'Journal was successfully updated.' }
          format.json { head :no_content }
        else
          format.html { render action: "edit" }
          format.json { render json: @journal.errors, status: :unprocessable_entity }
        end
      end
    end
  
    # DELETE /journals/1
    # DELETE /journals/1.json
    def destroy
      @journal = Journal.find(params[:id])
      @journal.destroy
  
      respond_to do |format|
        format.html { redirect_to journals_url }
        format.json { head :no_content }
      end
    end
  end
end
